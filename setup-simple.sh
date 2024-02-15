#!/bin/bash

# Set non-interactive environment
export DEBIAN_FRONTEND=noninteractive

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run the script as root."
    exit 1
fi

# Function for handling errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to add NFS entries to /etc/fstab
add_nfs_entries() {
    local_ip=$1
    remote_ip=$2
    mount_point=$3

    mkdir -p "$mount_point" || handle_error "Failed to create directory: $mount_point"
    echo "$remote_ip:/volume1/$local_ip $mount_point nfs defaults 0 0" >> /etc/fstab || handle_error "Failed to add NFS entry to /etc/fstab"
}

# Update and Upgrade
apt update && apt upgrade -y || handle_error "Failed to update and upgrade."

# Add system-wide aliases
echo "alias ll='ls -la'" >> /etc/bash.bashrc
echo "alias uur='apt update && apt full-upgrade -y && apt autoremove -y'" >> /etc/bash.bashrc

# NFS Configuration
add_nfs_entries WORKING 192.168.1.167 /mnt/WORKING
add_nfs_entries EMBY_MEDIA 192.168.1.167 /mnt/EMBY_MEDIA

# Display completion message
echo "Setup completed successfully."
