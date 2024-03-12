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
  #apt-get upgrade -y >> "$LOG_FILE" 2>&1
  apt-get upgrade -y 2>&1
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