#!/bin/sh

#######################################################################################
#                 Script for updating packages on Alpine Linux                        #
#                                                                                     #
#  path to script:  /etc/periodic/daily/update_packages.sh                            #
#  cronjob:         @daily @02:00                                                     #
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
  echo "*******************" >> "$LOG_FILE"
}

# Log timestamp and start of update
log "Starting package update"
log_separator

# Update package repositories
log "Updating package repositories..."
apk update >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  log "Error updating package repositories. Check $LOG_FILE for details."
  exit 1
fi
log_separator

# Upgrade installed packages
log "Upgrading installed packages..."
log "Checking for packages to be upgraded..."
packages_to_upgrade=$(apk upgrade -i -a --update-cache 2>&1 | awk '/Upgrading/ { print $3, $4 }')
if [ -z "$packages_to_upgrade" ]; then
  log "No packages to upgrade."
else
  log "Packages to be upgraded:"
  echo "$packages_to_upgrade" >> "$LOG_FILE" 2>&1
  log_separator

  log "Performing package upgrade..."
  apk upgrade -i -a --update-cache >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    log "Error upgrading installed packages. Check $LOG_FILE for details."
    exit 1
  fi
  log_separator

  # Log upgraded package versions
  log "Upgraded package versions:"
  apk info | awk '/^([^ ]+ [^ ]+ [^ ]+)/ { print $1, $2 }' >> "$LOG_FILE" 2>&1
fi

# Optionally check for configuration changes
# update-conf -a -l >> "$LOG_FILE" 2>&1
log_separator

# Log timestamp and end of update
log "Package update completed"
echo "" >> "$LOG_FILE"