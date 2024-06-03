#!/bin/bash

# Define the path to your OpenVPN configuration file
OVPN_FILE="ch-zur.prod.surfshark.com_udp.ovpn"

# Create a backup of the original configuration file
cp "$OVPN_FILE" "$OVPN_FILE.bak"

# Update the configuration file with necessary improvements
sed -i 's/^cipher .*/#&\ndata-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC/' "$OVPN_FILE"
sed -i 's/^ping .*/#&\nping 60\nping-restart 180/' "$OVPN_FILE"
sed -i 's/^auth .*/auth SHA512/' "$OVPN_FILE"
sed -i 's/^block-outside-dns/#&/' "$OVPN_FILE"
grep -q '^auth-nocache' "$OVPN_FILE" || echo 'auth-nocache' >> "$OVPN_FILE"

# Inform the user of the changes
echo "Updated $OVPN_FILE with the following changes:"
echo "- Added 'data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC'"
echo "- Added 'ping 60' and 'ping-restart 180'"
echo "- Updated 'auth' to 'auth SHA512'"
echo "- Commented out 'block-outside-dns'"
echo "- Added 'auth-nocache'"

# Display a message indicating the location of the backup file
echo "A backup of the original configuration file has been created at $OVPN_FILE.bak"

# Start OpenVPN in the background
openvpn --config "$OVPN_FILE" --daemon

# Inform the user that OpenVPN is running in the background
echo "OpenVPN has been started in the background using $OVPN_FILE"

# End of script
