#!/usr/bin/env bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/setup_script.log"
GITHUB_REPO_URL="https://raw.githubusercontent.com/0ldeuboi/linux-os-scripts/main/automation/"

# Function to print colored messages and log them
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" >>"$LOG_FILE"
}

# Function to handle errors
handle_error() {
    print_colored $RED "Error: $1"
    read -p "Do you want to skip this task and continue? (y/n): " choice
    case "$choice" in
    y | Y) print_colored $YELLOW "Skipping task..." ;;
    n | N)
        print_colored $RED "Terminating script."
        exit 1
        ;;
    *)
        print_colored $RED "Invalid choice. Terminating script."
        exit 1
        ;;
    esac
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_colored $RED "Please run the script as root."
    exit 1
fi

# Detect package manager and system type
if command -v apt-get &>/dev/null; then
    PACKAGE_MANAGER="apt-get"
    INSTALL_CMD="apt-get install -y"
    UPDATE_CMD="apt-get update -y"
    PACKAGE_CHECK="dpkg -l"
    PACKAGE_LIST="curl nfs-common alsa-utils wget sudo grep git ufw htop net-tools vim fail2ban tmux zip unzip build-essential software-properties-common rsync"
elif command -v apk &>/dev/null; then
    PACKAGE_MANAGER="apk"
    INSTALL_CMD="apk add --no-cache"
    UPDATE_CMD="apk update"
    PACKAGE_CHECK="apk list --installed"
    PACKAGE_LIST="curl nfs-utils alsa-utils wget sudo grep git ufw htop vim fail2ban tmux zip unzip build-base"
else
    print_colored $RED "Unsupported package manager. Please install the required packages manually."
    exit 1
fi

# Install dialog if not installed
if ! $PACKAGE_CHECK | grep -q dialog; then
    print_colored $BLUE "Installing dialog package..."
    $UPDATE_CMD
    $INSTALL_CMD dialog
fi

# Function to source scripts from GitHub when needed
source_script() {
    local script_url="$1"
    source <(curl -s -H "Authorization: token $GITHUB_TOKEN" "$script_url") || handle_error "Failed to source $script_url"
}

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
    1 | 18) source_script "$GITHUB_REPO_URL/update_upgrade.sh" && update_upgrade ;;
    2 | 18) source_script "$GITHUB_REPO_URL/add_aliases.sh" && add_aliases ;;
    3 | 18) source_script "$GITHUB_REPO_URL/install_packages.sh" && install_packages ;;
    4 | 18) source_script "$GITHUB_REPO_URL/create_user.sh" && create_user ;;
    5 | 18) source_script "$GITHUB_REPO_URL/configure_ufw.sh" && configure_ufw ;;
    6 | 18) source_script "$GITHUB_REPO_URL/configure_fail2ban.sh" && configure_fail2ban ;;
    7 | 18) source_script "$GITHUB_REPO_URL/configure_auto_updates.sh" && configure_auto_updates ;;
    8 | 18) source_script "$GITHUB_REPO_URL/optimize_ssh.sh" && optimize_ssh ;;
    9 | 18) source_script "$GITHUB_REPO_URL/configure_nfs.sh" && configure_nfs ;;
    10 | 18) source_script "$GITHUB_REPO_URL/create_update_script.sh" && create_update_script ;;
    11 | 18) source_script "$GITHUB_REPO_URL/install_dnscrypt.sh" && install_dnscrypt ;;
    12 | 18) source_script "$GITHUB_REPO_URL/configure_dns.sh" && configure_dns ;;
    13 | 18) source_script "$GITHUB_REPO_URL/create_dns_setup.sh" && create_dns_setup ;;
    14 | 18) source_script "$GITHUB_REPO_URL/create_cron_dns.sh" && create_cron_dns ;;
    15 | 18) source_script "$GITHUB_REPO_URL/create_vpn_check.sh" && create_vpn_check ;;
    16 | 18) source_script "$GITHUB_REPO_URL/create_vpn_service.sh" && create_vpn_service ;;
    17 | 18) source_script "$GITHUB_REPO_URL/configure_log_rotation.sh" && configure_log_rotation ;;
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

echo ""
print_colored $GREEN "Setup completed successfully. Install log can be found at $LOG_FILE"
read -p "Would you like to view the install log now? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    less $LOG_FILE
fi
