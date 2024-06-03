#!/bin/bash

# Set non-interactive environment
export DEBIAN_FRONTEND=noninteractive

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_colored() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Function for handling errors
handle_error() {
    print_colored $RED "Error: $1"
    read -p "Do you want to skip this task and continue? (y/n): " choice
    case "$choice" in 
        y|Y ) print_colored $YELLOW "Skipping task...";;
        n|N ) print_colored $RED "Terminating script."; exit 1;;
        * ) print_colored $RED "Invalid choice. Terminating script."; exit 1;;
    esac
}

# Function to add NFS entries to /etc/fstab
add_nfs_entries() {
    local_ip=$1
    remote_ip=$2
    mount_point=$3

    mkdir -p "$mount_point" || handle_error "Failed to create directory: $mount_point"
    echo "$remote_ip:/volume1/$local_ip $mount_point nfs defaults 0 0" >> /etc/fstab || handle_error "Failed to add NFS entry to /etc/fstab"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_colored $RED "Please run the script as root."
    exit 1
fi

# Update and Upgrade
print_colored $BLUE "Updating and Upgrading system packages..."
apt update && apt upgrade -y || handle_error "Failed to update and upgrade."

# Add system-wide aliases
print_colored $BLUE "Adding system-wide aliases..."
echo "alias ll='ls -la'" >> /etc/bash.bashrc
echo "alias uur='apt update && apt full-upgrade -y && apt autoremove -y'" >> /etc/bash.bashrc

# Install necessary packages
print_colored $BLUE "Installing necessary packages..."
packages_to_install=(
    "curl" "nfs-common" "alsa-utils" "wget" "sudo" "grep" "git" "ufw"
    "htop" "net-tools" "vim" "fail2ban" "tmux" "zip" "unzip" "build-essential"
    "software-properties-common" "rsync"
)
for package in "${packages_to_install[@]}"; do
    if dpkg -l | grep -q "^ii  $package "; then
        print_colored $YELLOW "Package $package is already installed. Updating..."
        apt upgrade -y "$package" || handle_error "Failed to update package: $package"
    else
        print_colored $YELLOW "Installing $package..."
        apt install -y "$package" || handle_error "Failed to install package: $package"
    fi
done

# Create user 'james' with password 'my_password'
if id "james" &>/dev/null; then
    print_colored $YELLOW "User 'james' already exists. Skipping creation."
else
    print_colored $BLUE "Creating user 'james'..."
    useradd -m -s /bin/bash james || handle_error "Failed to create user james"
    echo "james:3times3IS9" | chpasswd || handle_error "Failed to set password for james"
    usermod -aG sudo james || handle_error "Failed to add james to sudo group"

    # Copy SSH key from root to james
    print_colored $BLUE "Copying SSH public key from root to james..."
    mkdir -p /home/james/.ssh
    cp /root/.ssh/authorized_keys /home/james/.ssh/ || handle_error "Failed to copy SSH key"
    chown -R james:james /home/james/.ssh || handle_error "Failed to set permissions on /home/james/.ssh"
    chmod 700 /home/james/.ssh || handle_error "Failed to set permissions on /home/james/.ssh"
    chmod 600 /home/james/.ssh/authorized_keys || handle_error "Failed to set permissions on /home/james/.ssh/authorized_keys"
fi

# Enable UFW and allow OpenSSH
print_colored $BLUE "Configuring UFW (Uncomplicated Firewall)..."
ufw allow OpenSSH || handle_error "Failed to allow OpenSSH in UFW"
ufw enable || handle_error "Failed to enable UFW"

# Configure Fail2Ban
print_colored $BLUE "Configuring Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Configure automatic security updates
print_colored $BLUE "Configuring automatic security updates..."
apt install -y unattended-upgrades || handle_error "Failed to install unattended-upgrades"
dpkg-reconfigure -plow unattended-upgrades

# Optimize SSH configuration for security
print_colored $BLUE "Optimizing SSH configuration for security..."
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd || handle_error "Failed to restart SSH service"

# NFS Configuration
print_colored $BLUE "Configuring NFS..."
add_nfs_entries WORKING 192.168.1.168 /mnt/WORKING

# Create update_packages.sh script
print_colored $BLUE "Creating daily package update script..."
cat << 'EOF' > /etc/cron.daily/update_packages.sh
#!/bin/sh

#######################################################################################
#                 Script for updating packages on Debian Linux                        #
#                                                                                     #
#  path to script:  /etc/cron.daily/update_packages.sh                                #
#  cronjob:         Placed in /etc/cron.daily for daily execution                     #
#  path to log:     /var/log/update_packages.log                                      #
#                                                                                     #
#######################################################################################

# Set log file path
readonly LOG_FILE="/var/log/update_packages.log"

echo "****************$(date '+%Y-%m-%d %H:%M:%S')****************" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Function for logging with timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to log a separator with empty lines
log_separator() {
  echo "" >> "$LOG_FILE"
  echo "*******************" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
}

# Log timestamp and start of update
log "Starting package update"
log_separator

# Update package repositories
log "Updating package repositories..."
apt-get update >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  log "Error updating package repositories. Check $LOG_FILE for details."
  log_separator
  exit 1
fi
log_separator

# Upgrade installed packages
log "Upgrading installed packages..."
log "Checking for packages to be upgraded and their new versions..."
packages_to_upgrade=$(apt list --upgradable 2>/dev/null | awk 'NR>1 { print $1 }')

if [ -z "$packages_to_upgrade" ]; then
  log "No packages to upgrade."
else
  log "Packages to be upgraded and their new versions:"
  for pkg in $packages_to_upgrade; do
    new_version=$(apt list --upgradable 2>/dev/null | grep "^$pkg/" | awk '{print $2}')
    echo "$pkg $new_version" >> "$LOG_FILE"
  done
  log_separator
  
  log "Performing package upgrade..."
  apt-get upgrade -y >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    log "Error upgrading installed packages. Check $LOG_FILE for details."
    log_separator
    exit 1
  fi
  log_separator

  # Confirming versions of upgraded packages
  log "Confirming versions of upgraded packages:"
  for pkg in $packages_to_upgrade; do
    installed_version=$(dpkg -l | grep "^ii $pkg " | awk '{print $3}')
    echo "$pkg $installed_version" >> "$LOG_FILE"
  done
fi

log_separator

# Log timestamp and end of update
log "Package update completed"
echo "" >> "$LOG_FILE"
EOF

# Make the script executable
chmod +x /etc/cron.daily/update_packages.sh

# Final message with log file location
print_colored $GREEN "Setup completed successfully. Install log can be found at /var/log/update_packages.log"
read -p "Would you like to view the install log now? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    less /var/log/update_packages.log
fi

Incorperate this script in the same mannor