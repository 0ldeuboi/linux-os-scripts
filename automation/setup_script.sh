#!/usr/bin/env bash

# Function to set color variables using ANSI escape codes for formatting text in the terminal.
color() {
    YW=$(echo "\033[33m")
    BL=$(echo "\033[36m")
    RD=$(echo "\033[01;31m")
    BGN=$(echo "\033[4;92m")
    GN=$(echo "\033[1;92m")
    DGN=$(echo "\033[32m")
    CL=$(echo "\033[m")
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"
    BFR="\\r\\033[K"
    HOLD=" "
}

# Function to enable error handling in the script by setting options and defining a trap for the ERR signal.
catch_errors() {
    set -Eeuo pipefail
    trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

# Function called when an error occurs.
error_handler() {
    if [ -n "${SPINNER_PID-}" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    local exit_code="$?"
    local line_number="$1"
    local command="$2"
    local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
    echo -e "\n$error_message\n"
    exit_script
}

# Function to display a spinner.
spinner() {
    local chars="/-\|"
    local spin_i=0
    printf "\e[?25l"
    while true; do
        printf "\r \e[36m%s\e[0m" "${chars:spin_i++%${#chars}:1}"
        sleep 0.1
    done
}

# Function to display an informational message with a yellow color.
msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}   "
    spinner &
    SPINNER_PID=$!
}

# Function to display a success message with a green color.
msg_ok() {
    if [ -n "${SPINNER_PID-}" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

# Function to display an error message with a red color.
msg_error() {
    if [ -n "${SPINNER_PID-}" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

# This function is called when the user decides to exit the script.
exit_script() {
    clear
    echo -e "⚠  User exited script \n"
    exit
}

# Function to check if the shell is using bash.
shell_check() {
    if [[ "$(basename "$SHELL")" != "bash" ]]; then
        clear
        msg_error "Your default shell is not set to Bash. Please switch to Bash to use these scripts."
        echo -e "\nExiting..."
        sleep 2
        exit 1
    fi
}

# Function to ensure the script is run as root.
root_check() {
    if [[ "$(id -u)" -ne 0 ]]; then
        clear
        msg_error "Please run this script as root."
        echo -e "\nExiting..."
        sleep 2
        exit 1
    fi
}

# Function to check system architecture.
arch_check() {
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        echo -e "\n ${CROSS} This script will not work with PiMox! \n"
        echo -e "\n Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
        echo -e "Exiting..."
        sleep 2
        exit 1
    fi
}

# Initialize colors and error handling
color
catch_errors

# Check system requirements
shell_check
root_check
arch_check

# Define log file and other variables
LOG_FILE="/var/log/setup_script.log"
GITHUB_REPO_URL="https://raw.githubusercontent.com/0ldeuboi/linux-os-scripts/main/automation/"

# Function to print colored messages and log them
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${CL}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${message}" >>"$LOG_FILE"
}

# Function to handle errors
handle_error() {
    msg_error "Error: $1"
    read -p "Do you want to skip this task and continue? (y/n): " choice
    case "$choice" in
    y | Y) msg_info "Skipping task..." ;;
    n | N)
        msg_error "Terminating script."
        exit_script
        ;;
    *)
        msg_error "Invalid choice. Terminating script."
        exit_script
        ;;
    esac
}

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
    msg_error "Unsupported package manager. Please install the required packages manually."
    exit_script
fi

# Install dialog if not installed
if ! $PACKAGE_CHECK | grep -q dialog; then
    msg_info "Installing dialog package..."
    $UPDATE_CMD
    $INSTALL_CMD dialog
    msg_ok "Dialog installed successfully."
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
    1 | 18) source_script "$GITHUB_REPO_URL/update_upgrade.func" && update_upgrade ;;
    2 | 18) source_script "$GITHUB_REPO_URL/add_aliases.func" && add_aliases ;;
    3 | 18) source_script "$GITHUB_REPO_URL/install_packages.func" && install_packages ;;
    4 | 18) source_script "$GITHUB_REPO_URL/create_user.func" && create_user ;;
    5 | 18) source_script "$GITHUB_REPO_URL/configure_ufw.func" && configure_ufw ;;
    6 | 18) source_script "$GITHUB_REPO_URL/configure_fail2ban.func" && configure_fail2ban ;;
    7 | 18) source_script "$GITHUB_REPO_URL/configure_auto_updates.func" && configure_auto_updates ;;
    8 | 18) source_script "$GITHUB_REPO_URL/optimize_ssh.func" && optimize_ssh ;;
    9 | 18) source_script "$GITHUB_REPO_URL/configure_nfs.func" && configure_nfs ;;
    10 | 18) source_script "$GITHUB_REPO_URL/create_update_script.func" && create_update_script ;;
    11 | 18) source_script "$GITHUB_REPO_URL/install_dnscrypt.func" && install_dnscrypt ;;
    12 | 18) source_script "$GITHUB_REPO_URL/configure_dns.func" && configure_dns ;;
    13 | 18) source_script "$GITHUB_REPO_URL/create_dns_setup.func" && create_dns_setup ;;
    14 | 18) source_script "$GITHUB_REPO_URL/create_cron_dns.func" && create_cron_dns ;;
    15 | 18) source_script "$GITHUB_REPO_URL/create_vpn_check.func" && create_vpn_check ;;
    16 | 18) source_script "$GITHUB_REPO_URL/create_vpn_service.func" && create_vpn_service ;;
    17 | 18) source_script "$GITHUB_REPO_URL/configure_log_rotation.func" && configure_log_rotation ;;
    *)
        msg_error "Invalid choice. Exiting."
        exit_script
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
msg_ok "Setup completed successfully. Install log can be found at $LOG_FILE"
read -p "Would you like to view the install log now? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    less $LOG_FILE
fi
