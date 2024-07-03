#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD_GREEN='\033[1;92m'
DARK_GREEN='\033[32m'
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
BFR="\\r\\033[K"
HOLD=" "

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
    local error_message="${RED}[ERROR]${NC} in line ${RED}$line_number${NC}: exit code ${RED}$exit_code${NC}: while executing command ${YELLOW}$command${NC}"
    echo -e "\n$error_message\n"
    exit_script
}

# Function to check if the script is running as root.
root_check() {
    if [[ "$EUID" -ne 0 ]]; then
        msg_error "This script must be run as root. Please run again with sudo or as root."
        exit 1
    fi
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
    echo -ne " ${HOLD} ${YELLOW}${msg}   "
    spinner &
    SPINNER_PID=$!
}

# Function to display a success message with a green color.
msg_ok() {
    if [ -n "${SPINNER_PID-}" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    local msg="$1"
    echo -e "${BFR} ${CHECK} ${GREEN}${msg}${NC}"
}

# Function to display an error message with a red color.
msg_error() {
    if [ -n "${SPINNER_PID-}" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
    printf "\e[?25h"
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RED}${msg}${NC}"
}

# This function is called when the user decides to exit the script.
exit_script() {
    clear
    echo -e "⚠  User exited script \n"
    exit
}

# Utility function to detect package manager and set commands.
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PACKAGE_MANAGER="apt-get"
        INSTALL_CMD="apt-get install -y"
        UPDATE_CMD="apt-get update -y"
        PACKAGE_CHECK="dpkg -l"
    elif command -v apk &>/dev/null; then
        PACKAGE_MANAGER="apk"
        INSTALL_CMD="apk add --no-cache"
        UPDATE_CMD="apk update"
        PACKAGE_CHECK="apk list --installed"
    else
        msg_error "Unsupported package manager. Please install the required packages manually."
        exit_script
    fi
}

# Utility function to install packages.
install_package() {
    local package=$1
    if ! $PACKAGE_CHECK | grep -q "$package"; then
        msg_info "Installing $package..."
        $INSTALL_CMD $package || handle_error "Failed to install $package"
        msg_ok "$package installed successfully."
    else
        msg_ok "$package is already installed."
    fi
}

# Initialize error handling
catch_errors

# Check system requirements
root_check
detect_package_manager

# Define log file and other variables
LOG_FILE="/var/log/setup_script.log"
GITHUB_REPO_URL="https://raw.githubusercontent.com/0ldeuboi/linux-os-scripts/main/automation"

# Function to print colored messages and log them
print_colored() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
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

# Check if the script is already running in bash
if [[ -z "$BASH_VERSION" ]]; then
    if command -v apk &>/dev/null; then
        # Install bash if not already installed on Alpine Linux
        if ! command -v bash &>/dev/null; then
            msg_info "Installing bash on Alpine Linux..."
            apk add bash
            msg_ok "Bash installed successfully."
        fi

        # Switch to bash and source .bashrc
        msg_info "Switching to bash and sourcing .bashrc..."
        echo "source /etc/profile.d/aliases.sh" >>"$HOME/.bashrc"
        exec /bin/bash -c "source $HOME/.bashrc; exec /bin/bash"
    else
        msg_error "Bash is required to run this script. Please install bash and try again."
        exit 1
    fi
fi

# Install dialog if not installed
install_package "dialog"

# Function to source scripts from GitHub when needed
source_script() {
    local script_url="$1"
    echo "Sourcing script from: $script_url" # Debug statement
    curl -s "$script_url" -o /tmp/temp_script.sh
    if [ $? -ne 0 ]; then
        handle_error "Failed to download $script_url"
    fi
    source /tmp/temp_script.sh || handle_error "Failed to source $script_url"
    rm -f /tmp/temp_script.sh
}

# Define the options for the checklist
cmd=(dialog --separate-output --checklist "Select options:" 22 76 12)
options=(
    1 "Add System-wide Aliases" off
    2 "Install Necessary Packages" off
    3 "User and Security Configuration" off
    4 "Configure UFW and Fail2Ban" off
    5 "Configure NFS" off
    6 "DNS and Network Configuration" off
    7 "Create Automatic Security Updates & Daily Package Updates" off
    8 "Configure VPN and Log Rotation" off
    9 "Run All Actions" off
)

# Capture the selections from the user
choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
clear

# Debug: print selected choices
echo "Selected choices: ${choices[@]}"

# Function to run actions
run_actions() {
    local choice=$1
    echo "Running action for choice: $choice" # Debug statement
    case $choice in
    1 | 9)
        echo "Sourcing and running add_aliases" # Debug statement
        source_script "$GITHUB_REPO_URL/configure_aliases.func"
        add_aliases
        ;;
    2 | 9)
        echo "Sourcing and running update_upgrade and install_packages" # Debug statement
        source_script "$GITHUB_REPO_URL/update_upgrade.func"
        update_upgrade
        source_script "$GITHUB_REPO_URL/install_packages.func"
        install_packages
        ;;
    3 | 9)
        echo "Sourcing and running create_user_james and optimise_ssh" # Debug statement
        source_script "$GITHUB_REPO_URL/create_user_james.func"
        create_user_james
        source_script "$GITHUB_REPO_URL/optimise_ssh.func"
        optimise_ssh
        ;;
    4 | 9)
        echo "Sourcing and running configure_ufw and configure_fail2ban" # Debug statement
        source_script "$GITHUB_REPO_URL/configure_ufw.func"
        configure_ufw
        source_script "$GITHUB_REPO_URL/configure_fail2ban.func"
        configure_fail2ban
        ;;
    5 | 9)
        echo "Sourcing and running configure_nfs" # Debug statement
        source_script "$GITHUB_REPO_URL/configure_nfs.func"
        add_nfs_entries
        ;;
    6 | 9)
        echo "Sourcing and running DNS and Network Configuration scripts" # Debug statement
        source_script "$GITHUB_REPO_URL/install_dnscrypt_proxy.func"
        install_dnscrypt_proxy
        source_script "$GITHUB_REPO_URL/configure_dnscrypt_proxy.func"
        configure_dnscrypt_proxy
        source_script "$GITHUB_REPO_URL/set_custom_dns.func"
        set_custom_dns
        source_script "$GITHUB_REPO_URL/create_dns_setup_script.func"
        create_dns_setup_script
        source_script "$GITHUB_REPO_URL/create_dns_cron_job.func"
        create_dns_cron_job
        ;;
    7 | 9)
        echo "Sourcing and running auto updates and daily package updates scripts" # Debug statement
        source_script "$GITHUB_REPO_URL/configure_auto_updates.func"
        configure_auto_updates
        source_script "$GITHUB_REPO_URL/create_daily_update_script.func"
        create_daily_update_script
        ;;
    8 | 9)
        echo "Sourcing and running VPN and Log Rotation scripts" # Debug statement
        source_script "$GITHUB_REPO_URL/create_vpn_check_script.func"
        create_vpn_check_script
        source_script "$GITHUB_REPO_URL/create_vpn_check_service.func"
        create_vpn_check_service
        source_script "$GITHUB_REPO_URL/configure_log_rotation.func"
        configure_log_rotation
        ;;
    *)
        echo "Invalid choice. Exiting." # Debug statement
        exit 1
        ;;
    esac
}

# Run selected actions sequentially
for choice in ${choices[@]}; do
    run_actions $choice
done

echo ""
echo "Setup completed successfully. Install log can be found at $LOG_FILE"
read -p "Would you like to view the install log now? (y/n): " view_log
if [[ "$view_log" == "y" || "$view_log" == "Y" ]]; then
    less $LOG_FILE
fi
