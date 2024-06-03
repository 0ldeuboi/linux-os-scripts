#!/bin/bash

# Set non-interactive environment
export DEBIAN_FRONTEND=noninteractive

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/setup_script.log"

# Function to print colored messages and log them
print_colored() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" >> "$LOG_FILE"
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

    print_colored $BLUE "Creating mount point: $mount_point"
    mkdir -p "$mount_point" || handle_error "Failed to create directory: $mount_point"
    
    print_colored $BLUE "Adding NFS entry to /etc/fstab"
    echo "$remote_ip:/volume1/$local_ip $mount_point nfs defaults 0 0" >> /etc/fstab || handle_error "Failed to add NFS entry to /etc/fstab"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_colored $RED "Please run the script as root."
    exit 1
fi

# Install dialog if not installed
if ! dpkg -l | grep -q dialog; then
    print_colored $BLUE "Installing dialog package..."
    apt-get update -y
    apt-get install -y dialog
fi

# Prompt for OpenVPN credentials
read -p "Enter OpenVPN username: " vpn_username
read -sp "Enter OpenVPN password: " vpn_password
echo

# Save OpenVPN credentials to a file
VPN_CREDENTIALS_FILE="/etc/openvpn/credentials"
print_colored $BLUE "Saving OpenVPN credentials to $VPN_CREDENTIALS_FILE"
echo "$vpn_username" > "$VPN_CREDENTIALS_FILE"
echo "$vpn_password" >> "$VPN_CREDENTIALS_FILE"
chmod 600 "$VPN_CREDENTIALS_FILE"

# Define the options for the checklist
cmd=(dialog --separate-output --checklist "Select options:" 22 76 16)
options=(
    1 "Update and Upgrade System" off
    2 "Add System-wide Aliases" off
    3 "Install Necessary Packages" off
    4 "Create User 'james'" off
    5 "Configure UFW" off
    6 "Configure Fail2Ban" off
    7 "Configure Automatic Security Updates" off
    8 "Optimize SSH Configuration" off
    9 "Configure NFS" off
    10 "Create Daily Package Update Script" off
    11 "Install and Configure DNSCrypt-Proxy" off
    12 "Configure Custom DNS" off
    13 "Create DNS Setup Script" off
    14 "Create Cron Job for DNS Setup" off
    15 "Create VPN Check Script" off
    16 "Create Systemd Service for VPN Check" off
    17 "Configure Log Rotation" off
    18 "Run All Actions" off
)

choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
clear

# Function to run actions
run_actions() {
    local choice=$1
    case $choice in
        1|18)
            print_colored $BLUE "Updating and Upgrading system packages..."
            apt-get update -y && apt-get upgrade -y || handle_error "Failed to update and upgrade."
            print_colored $GREEN "System update and upgrade completed."
            ;;
        2|18)
            print_colored $BLUE "Adding system-wide aliases..."
            echo "alias ll='ls -la'" >> /etc/bash.bashrc
            echo "alias uur='apt update && apt full-upgrade -y && apt autoremove -y'" >> /etc/bash.bashrc
            source /etc/bash.bashrc
            print_colored $GREEN "System-wide aliases added."
            ;;
        3|18)
            print_colored $BLUE "Installing necessary packages..."
            packages_to_install=(
                "curl" "nfs-common" "alsa-utils" "wget" "sudo" "grep" "git" "ufw"
                "htop" "net-tools" "vim" "fail2ban" "tmux" "zip" "unzip" "build-essential"
                "software-properties-common" "rsync"
            )
            for package in "${packages_to_install[@]}"; do
                if dpkg -l | grep -q "^ii  $package "; then
                    print_colored $YELLOW "Package $package is already installed. Updating..."
                    apt-get upgrade -y "$package" || handle_error "Failed to update package: $package"
                else
                    print_colored $YELLOW "Installing $package..."
                    apt-get install -y "$package" || handle_error "Failed to install package: $package"
                fi
            done
            print_colored $GREEN "Necessary packages installation completed."
            ;;
        4|18)
            if id "james" &>/dev/null; then
                print_colored $YELLOW "User 'james' already exists. Skipping creation."
            else
                print_colored $BLUE "Creating user 'james'..."
                useradd -m -s /bin/bash james || handle_error "Failed to create user james"
                
                read -sp "Enter password for user 'james': " user_password
                echo
                echo "james:$user_password" | chpasswd || handle_error "Failed to set password for james"
                usermod -aG sudo james || handle_error "Failed to add james to sudo group"

                print_colored $BLUE "Please enter the SSH public key for the user 'james':"
                read -p "SSH Public Key: " ssh_key

                mkdir -p /home/james/.ssh || handle_error "Failed to create .ssh directory for james"
                echo "$ssh_key" > /home/james/.ssh/authorized_keys || handle_error "Failed to write SSH public key"
                chown -R james:james /home/james/.ssh || handle_error "Failed to set permissions on /home/james/.ssh"
                chmod 700 /home/james/.ssh || handle_error "Failed to set permissions on /home/james/.ssh"
                chmod 600 /home/james/.ssh/authorized_keys || handle_error "Failed to set permissions on /home/james/.ssh/authorized_keys"
            fi
            print_colored $GREEN "User 'james' creation and configuration completed."
            ;;
        5|18)
            print_colored $BLUE "Configuring UFW (Uncomplicated Firewall)..."
            ufw allow OpenSSH || handle_error "Failed to allow OpenSSH in UFW"
            ufw enable || handle_error "Failed to enable UFW"
            print_colored $GREEN "UFW configuration completed."
            ;;
        6|18)
            print_colored $BLUE "Configuring Fail2Ban..."
            systemctl enable fail2ban
            systemctl start fail2ban
            print_colored $GREEN "Fail2Ban configuration completed."
            ;;
        7|18)
            print_colored $BLUE "Configuring automatic security updates..."
            apt-get install -y unattended-upgrades || handle_error "Failed to install unattended-upgrades"
            dpkg-reconfigure -plow unattended-upgrades
            print_colored $GREEN "Automatic security updates configuration completed."
            ;;
        8|18)
            print_colored $BLUE "Optimizing SSH configuration for security..."
            sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
            systemctl restart sshd || handle_error "Failed to restart SSH service"
            print_colored $GREEN "SSH configuration optimization completed."
            ;;
        9|18)
            print_colored $BLUE "Configuring NFS..."
            add_nfs_entries WORKING 192.168.1.168 /mnt/WORKING
            print_colored $GREEN "NFS configuration completed."
            ;;
        10|18)
            print_colored $BLUE "Creating daily package update script..."
            cat << 'EOF' > /etc/cron.daily/update_packages.sh
#!/bin/sh

LOG_FILE="/var/log/update_packages.log"

echo "****************$(date '+%Y-%m-%d %H:%M:%S')****************" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_separator() {
  echo "" >> "$LOG_FILE"
  echo "*******************" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
}

log "Starting package update"
log_separator

log "Updating package repositories..."
apt-get update >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  log "Error updating package repositories. Check $LOG_FILE for details."
  log_separator
  exit 1
fi
log_separator

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

  log "Confirming versions of upgraded packages:"
  for pkg in $packages_to_upgrade; do
    installed_version=$(dpkg -l | grep "^ii $pkg " | awk '{print $3}')
    echo "$pkg $installed_version" >> "$LOG_FILE"
  done
fi

log_separator

log "Package update completed"
echo "" >> "$LOG_FILE"
EOF
            chmod +x /etc/cron.daily/update_packages.sh

            print_colored $BLUE "Configuring log rotation for update_packages.log..."
            cat <<EOF > /etc/logrotate.d/update_packages
/var/log/update_packages.log {
    monthly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    postrotate
        /bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
            print_colored $GREEN "Daily package update script creation and log rotation configuration completed."
            ;;
        11|18)
            print_colored $BLUE "Installing dnscrypt-proxy..."
            apt-get update && apt-get install -y dnscrypt-proxy || handle_error "Failed to install dnscrypt-proxy."
            print_colored $GREEN "dnscrypt-proxy installation completed."
            ;;
        12|18)
            print_colored $BLUE "Configuring dnscrypt-proxy..."
            cat <<EOF > /etc/dnscrypt-proxy/dnscrypt-proxy.toml
server_names = ['custom-adguard-doh', 'custom-adguard-dot', 'custom-adguard-doq']

[static]
  [static.'custom-adguard-doh']
    stamp = 'sdns://AgcAAAAAAAAAAAAPZG5zLWRvaC5leGFtcGxlLmNvbQovZG5zLXF1ZXJ5'
  [static.'custom-adguard-dot']
    stamp = 'sdns://AQcAAAAAAAAAD2Rucy1kb3QuZXhhbXBsZS5jb20KL2Rucy1xdWVyeQ'
  [static.'custom-adguard-doq']
    stamp = 'sdns://AgcAAAAAAAAAAAAPZG5zLWRvcS5leGFtcGxlLmNvbQovZG5zLXF1ZXJ5'

listen_addresses = ['127.0.2.1:53']
EOF
            systemctl restart dnscrypt-proxy || handle_error "Failed to restart dnscrypt-proxy."
            print_colored $GREEN "dnscrypt-proxy configuration completed."
            ;;
        13|18)
            print_colored $BLUE "Setting custom DNS server to 127.0.2.1..."
            echo "nameserver 127.0.2.1" > /etc/resolv.conf || handle_error "Failed to set custom DNS server."

            if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
                if ! grep -q "dns=none" /etc/NetworkManager/NetworkManager.conf; then
                    echo "[main]" >> /etc/NetworkManager/NetworkManager.conf
                    echo "dns=none" >> /etc/NetworkManager/NetworkManager.conf
                fi

                print_colored $BLUE "Restarting NetworkManager..."
                systemctl restart NetworkManager || handle_error "Failed to restart NetworkManager."
            else
                print_colored $YELLOW "NetworkManager is not installed. Skipping NetworkManager configuration."
            fi
            print_colored $GREEN "Custom DNS server configuration completed."
            ;;
        14|18)
            print_colored $BLUE "Creating DNS setup script..."
            cat <<EOF > /usr/local/bin/set_dns.sh
#!/bin/bash
echo "nameserver 127.0.2.1" > /etc/resolv.conf

if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    if ! grep -q "dns=none" /etc/NetworkManager/NetworkManager.conf; then
        echo "[main]" >> /etc/NetworkManager/NetworkManager.conf
        echo "dns=none" >> /etc/NetworkManager/NetworkManager.conf
    fi
    systemctl restart NetworkManager
fi
EOF
            chmod +x /usr/local/bin/set_dns.sh || handle_error "Failed to create DNS setup script."
            print_colored $GREEN "DNS setup script creation completed."
            ;;
        15|18)
            print_colored $BLUE "Creating cron job to run DNS setup script at reboot..."
            echo "@reboot root /usr/local/bin/set_dns.sh" > /etc/cron.d/set_dns || handle_error "Failed to create cron job."
            print_colored $GREEN "Cron job for DNS setup script creation completed."
            ;;
        16|18)
            print_colored $BLUE "Creating VPN check script..."
            cat <<EOF > /usr/local/bin/vpn_check.sh
#!/bin/bash

CONFIG_FILE="/etc/vpn_check.conf"
LOG_FILE="/var/log/vpn_check.log"

# Load configuration
if [ -f "\$CONFIG_FILE" ]; then
    source "\$CONFIG_FILE"
else
    echo "\$(date): Configuration file not found: \$CONFIG_FILE" | tee -a \$LOG_FILE
    exit 1
fi

# Function to check VPN connection
check_vpn_connection() {
    if ping -c 1 8.8.8.8 &> /dev/null; then
        return 0 # VPN is connected
    else
        return 1 # VPN is not connected
    fi
}

# Function to restart OpenVPN service
restart_openvpn() {
    echo "\$(date): VPN connection is down. Restarting OpenVPN service..." | tee -a \$LOG_FILE
    sudo systemctl restart \$OPENVPN_SERVICE
    if [ \$? -eq 0 ]; then
        echo "\$(date): OpenVPN service restarted successfully." | tee -a \$LOG_FILE
    else
        echo "\$(date): Failed to restart OpenVPN service." | tee -a \$LOG_FILE
    fi
}

# Function to check VPN country
check_vpn_country() {
    CURRENT_COUNTRY=\$(curl -s https://ipinfo.io/country)
    
    if [ "\$CURRENT_COUNTRY" == "\$VPN_COUNTRY" ]; then
        return 0 # VPN is working correctly
    else
        return 1 # VPN is not working correctly
    fi
}

# Main loop
while true; do
    if check_vpn_connection && check_vpn_country; then
        echo "\$(date): VPN connection is active and country is correct (\$VPN_COUNTRY)." | tee -a \$LOG_FILE
    else
        restart_openvpn
    fi
    sleep 1h
done
EOF

chmod +x /usr/local/bin/vpn_check.sh || handle_error "Failed to create VPN check script."

print_colored $BLUE "Creating VPN check configuration..."
cat <<EOF > /etc/vpn_check.conf
# VPN check configuration
OPENVPN_SERVICE="openvpn@ch-zur.prod.surfshark.com_udp" # Adjust this to match your service name
VPN_COUNTRY="CH"
EOF
            print_colored $GREEN "VPN check script and configuration creation completed."
            ;;
        17|18)
            print_colored $BLUE "Creating systemd service..."
            cat <<EOF > /etc/systemd/system/vpn_check.service
[Unit]
Description=VPN Connection Check and Restart Service
After=network.target

[Service]
ExecStart=/usr/local/bin/vpn_check.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable vpn_check.service || handle_error "Failed to enable vpn_check.service."
            systemctl start vpn_check.service || handle_error "Failed to start vpn_check.service."
            print_colored $GREEN "Systemd service for VPN check creation completed."
            ;;
        17|18)
            print_colored $BLUE "Configuring log rotation..."
            cat <<EOF > /etc/logrotate.d/vpn_check
/var/log/vpn_check.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    postrotate
        systemctl restart vpn_check.service > /dev/null 2>&1 || true
    endscript
}
EOF
            print_colored $GREEN "Log rotation configuration for VPN check completed."
            ;;
        *)
            print_colored $RED "Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

if [[ " ${choices[@]} " =~ " 18 " ]]; then
    for i in {1..17}; do
        run_actions $i
    done
else
    for choice in ${choices[@]}; do
        run_actions $choice
    done
fi

# Define the options for the verification checklist
verification_cmd=(dialog --separate-output --checklist "Select verification checks:" 22 76 16)
verification_options=(
    1 "System Update and Upgrade" off
    2 "System-wide Aliases" off
    3 "Installed Packages" off
    4 "User Creation" off
    5 "UFW Status" off
    6 "Fail2Ban Status" off
    7 "Automatic Security Updates" off
    8 "SSH Configuration" off
    9 "NFS Configuration" off
    10 "Daily Package Update Script" off
    11 "dnscrypt-proxy Status" off
    12 "Custom DNS Configuration" off
    13 "DNS Setup Script" off
    14 "Cron Job for DNS Setup Script" off
    15 "VPN Check Script" off
    16 "VPN Check Systemd Service" off
    17 "Log Rotation Configuration" off
)

verification_choices=$("${verification_cmd[@]}" "${verification_options[@]}" 2>&1 >/dev/tty)
clear

# Function to run verification checks
run_verification() {
    local choice=$1
    case $choice in
        1)
            print_colored $BLUE "Verifying System Update and Upgrade..."
            if apt-get update -y && apt-get upgrade -y; then
                print_colored $GREEN "System update and upgrade verification passed."
            else
                print_colored $RED "System update and upgrade verification failed."
            fi
            ;;
        2)
            print_colored $BLUE "Verifying System-wide Aliases..."
            if grep -q "alias ll='ls -la'" /etc/bash.bashrc && grep -q "alias uur='apt update && apt full-upgrade -y && apt autoremove -y'" /etc/bash.bashrc; then
                print_colored $GREEN "System-wide aliases are correctly set."
            else
                print_colored $RED "System-wide aliases are not set correctly."
            fi
            ;;
        3)
            print_colored $BLUE "Verifying Installed Packages..."
            all_installed=true
            for package in "${packages_to_install[@]}"; do
                if dpkg -l | grep -q "$package"; then
                    print_colored $GREEN "Package $package is installed."
                else
                    print_colored $RED "Package $package is not installed."
                    all_installed=false
                fi
            done
            if $all_installed; then
                print_colored $GREEN "All necessary packages are installed."
            else
                print_colored $RED "Some necessary packages are missing."
            fi
            ;;
        4)
            print_colored $BLUE "Verifying User Creation..."
            if id james &>/dev/null; then
                print_colored $GREEN "User 'james' exists."
                sudo -l -U james
            else
                print_colored $RED "User 'james' does not exist."
            fi
            ;;
        5)
            print_colored $BLUE "Verifying UFW Status..."
            if ufw status | grep -q "Status: active"; then
                print_colored $GREEN "UFW is active."
            else
                print_colored $RED "UFW is not active."
            fi
            ;;
        6)
            print_colored $BLUE "Verifying Fail2Ban Status..."
            if systemctl is-active --quiet fail2ban; then
                print_colored $GREEN "Fail2Ban is active."
            else
                print_colored $RED "Fail2Ban is not active."
            fi
            ;;
        7)
            print_colored $BLUE "Verifying Automatic Security Updates..."
            if grep -q "APT::Periodic::Update-Package-Lists \"1\";" /etc/apt/apt.conf.d/20auto-upgrades && grep -q "APT::Periodic::Unattended-Upgrade \"1\";" /etc/apt/apt.conf.d/20auto-upgrades; then
                print_colored $GREEN "Automatic security updates are configured correctly."
            else
                print_colored $RED "Automatic security updates are not configured correctly."
            fi
            ;;
        8)
            print_colored $BLUE "Verifying SSH Configuration..."
            if sshd -T | grep -q "permitrootlogin no" && sshd -T | grep -q "passwordauthentication no"; then
                print_colored $GREEN "SSH configuration is optimized for security."
            else
                print_colored $RED "SSH configuration is not optimized for security."
            fi
            ;;
        9)
            print_colored $BLUE "Verifying NFS Configuration..."
            if grep -q "/mnt/WORKING" /etc/fstab; then
                print_colored $GREEN "NFS is configured correctly."
            else
                print_colored $RED "NFS is not configured correctly."
            fi
            ;;
        10)
            print_colored $BLUE "Verifying Daily Package Update Script..."
            if [ -f /etc/cron.daily/update_packages.sh ]; then
                print_colored $GREEN "Daily package update script exists."
                cat /etc/cron.daily/update_packages.sh
            else
                print_colored $RED "Daily package update script does not exist."
            fi
            ;;
        11)
            print_colored $BLUE "Verifying dnscrypt-proxy Status..."
            if systemctl is-active --quiet dnscrypt-proxy; then
                print_colored $GREEN "dnscrypt-proxy is active."
            else
                print_colored $RED "dnscrypt-proxy is not active."
            fi
            ;;
        12)
            print_colored $BLUE "Verifying Custom DNS Configuration..."
            if grep -q "nameserver 127.0.2.1" /etc/resolv.conf; then
                print_colored $GREEN "Custom DNS configuration is set correctly."
            else
                print_colored $RED "Custom DNS configuration is not set correctly."
            fi
            ;;
        13)
            print_colored $BLUE "Verifying DNS Setup Script..."
            if [ -f /usr/local/bin/set_dns.sh ]; then
                print_colored $GREEN "DNS setup script exists."
                cat /usr/local/bin/set_dns.sh
            else
                print_colored $RED "DNS setup script does not exist."
            fi
            ;;
        14)
            print_colored $BLUE "Verifying Cron Job for DNS Setup Script..."
            if [ -f /etc/cron.d/set_dns ]; then
                print_colored $GREEN "Cron job for DNS setup script exists."
                cat /etc/cron.d/set_dns
            else
                print_colored $RED "Cron job for DNS setup script does not exist."
            fi
            ;;
        15)
            print_colored $BLUE "Verifying VPN Check Script..."
            if [ -f /usr/local/bin/vpn_check.sh ]; then
                print_colored $GREEN "VPN check script exists."
                cat /usr/local/bin/vpn_check.sh
                cat /etc/vpn_check.conf
            else
                print_colored $RED "VPN check script does not exist."
            fi
            ;;
        16)
            print_colored $BLUE "Verifying VPN Check Systemd Service..."
            if systemctl is-active --quiet vpn_check.service; then
                print_colored $GREEN "VPN check systemd service is active."
            else
                print_colored $RED "VPN check systemd service is not active."
            fi
            ;;
        17)
            print_colored $BLUE "Verifying Log Rotation Configuration..."
            if [ -f /etc/logrotate.d/vpn_check ]; then
                print_colored $GREEN "Log rotation configuration for VPN check exists."
                cat /etc/logrotate.d/vpn_check
            else
                print_colored $RED "Log rotation configuration for VPN check does not exist."
            fi
            ;;
        18)
            print_colored $GREEN "Exiting verification checks."
            exit 0
            ;;
        *)
            print_colored $RED "Invalid choice."
            ;;
    esac
}


for choice in ${verification_choices[@]}; do
    run_verification $choice
done

echo ""
print_colored $GREEN "Setup and verification completed successfully. Install log can be found at $LOG_FILE"
read -p "Would you like to view the install log now? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    less $LOG_FILE
fi
