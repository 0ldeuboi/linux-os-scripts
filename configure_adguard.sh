#!/bin/bash

# Variables
SERVER_IP="192.168.1.183"
REVERSE_PROXY_IP="192.168.1.190"
CLOUDFLARE_TUNNEL_IP="192.168.1.249"
WIFI_AP_IP="192.168.1.3"
ADGUARD_CONFIG="/opt/AdGuardHome/AdGuardHome.yaml"
CLOUDFLARE_IPS_V4_URL="https://www.cloudflare.com/ips-v4"
CLOUDFLARE_IPS_V6_URL="https://www.cloudflare.com/ips-v6"
TEMP_DNS_SERVER="1.1.1.1"
DOMAIN="adguard.myhomenet.casa"
SPECIFIC_IPS=("89.37.94.113" "90.251.254.22")

TUNNEL_IPS_V4=("198.41.192.167" "198.41.192.67" "198.41.192.57" "198.41.192.107" "198.41.192.27" "198.41.192.7" "198.41.192.227" "198.41.192.47" "198.41.192.37" "198.41.192.77" "198.41.200.13" "198.41.200.193" "198.41.200.3" "198.41.200.233" "198.41.200.53" "198.41.200.63" "198.41.200.113" "198.41.200.73" "198.41.200.43" "198.41.200.23")
TUNNEL_IPS_V6=("2606:4700:a0::1" "2606:4700:a0::2" "2606:4700:a0::3" "2606:4700:a0::4" "2606:4700:a0::5" "2606:4700:a0::6" "2606:4700:a0::7" "2606:4700:a0::8" "2606:4700:a0::9" "2606:4700:a0::10" "2606:4700:a8::1" "2606:4700:a8::2" "2606:4700:a8::3" "2606:4700:a8::4" "2606:4700:a8::5" "2606:4700:a8::6" "2606:4700:a8::7" "2606:4700:a8::8" "2606:4700:a8::9" "2606:4700:a8::10")
OPTIONAL_IPS_V4=("104.19.192.29" "104.19.192.177" "104.19.192.175" "104.19.193.29" "104.19.192.174" "104.19.192.176" "104.18.25.129" "104.18.24.129" "104.19.194.29" "104.19.195.29" "104.18.4.64" "104.18.5.64")
OPTIONAL_IPS_V6=("2606:4700:300a::6813:c0af" "2606:4700:300a::6813:c01d" "2606:4700:300a::6813:c0ae" "2606:4700:300a::6813:c11d" "2606:4700:300a::6813:c0b0" "2606:4700:300a::6813:c0b1" "2606:4700::6812:1881" "2606:4700::6812:1981" "2606:4700:300a::6813:c31d" "2606:4700:300a::6813:c21d" "2606:4700::6812:540" "2606:4700::6812:440")

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to execute a command and check its success
execute_command() {
    eval "$1"
    if [[ $? -ne 0 ]]; then
        log "Error executing: $1"
        exit 1
    fi
}

# Function to check if a rule already exists
rule_exists() {
    iptables -C "$@" 2>/dev/null
}

# Function to temporarily allow all DNS traffic
allow_dns_traffic() {
    log "Temporarily allowing all DNS traffic..."
    iptables -D INPUT -p udp --dport 53 -j DROP 2>/dev/null
    iptables -D INPUT -p tcp --dport 53 -j DROP 2>/dev/null
    rule_exists INPUT -p udp --dport 53 -j ACCEPT || iptables -A INPUT -p udp --dport 53 -j ACCEPT
    rule_exists INPUT -p tcp --dport 53 -j ACCEPT || iptables -A INPUT -p tcp --dport 53 -j ACCEPT
    log "All DNS traffic temporarily allowed."
}

# Function to set temporary DNS server
set_temporary_dns() {
    log "Setting temporary DNS server to $TEMP_DNS_SERVER..."
    echo "nameserver $TEMP_DNS_SERVER" >/etc/resolv.conf
    log "Temporary DNS server set."
}

# Function to restore original DNS server
restore_original_dns() {
    log "Restoring original DNS server..."
    if [[ -f $BACKUP_RESOLV_CONF ]]; then
        cp $BACKUP_RESOLV_CONF /etc/resolv.conf
        log "Original DNS server restored."
    else
        log "Backup resolv.conf not found, please check manually."
    fi
}

# Function to install necessary packages
install_packages() {
    log "Installing necessary packages..."
    execute_command "apt-get update"
    execute_command "apt-get install -y iptables iptables-persistent ufw wget"
    log "Packages installed."
}

# Function to update AdGuard configuration
update_adguard_config() {
    log "Updating AdGuard Home configuration..."
    backup_file="${ADGUARD_CONFIG}.bak.$(date +'%Y%m%d%H%M%S')"
    cp $ADGUARD_CONFIG $backup_file
    log "Backup of AdGuard Home configuration created at $backup_file"

    # Read the existing bind_hosts section, if any, excluding 0.0.0.0
    existing_bind_hosts=$(sed -n '/bind_hosts:/,/[^ ]/p' $ADGUARD_CONFIG | grep -v "0.0.0.0" | grep -v "127.0.0.1" | grep -v "$SERVER_IP")

    # Initialize the new bind_hosts list with the desired IPs
    new_bind_hosts="- $SERVER_IP\n    - 127.0.0.1"

    # Add the existing bind_hosts entries to the new list if they are not duplicates
    if [ -n "$existing_bind_hosts" ]; then
        while read -r line; do
            if [[ ! $line =~ $SERVER_IP ]] && [[ ! $line =~ 127.0.0.1 ]]; then
                new_bind_hosts+="\n    $line"
            fi
        done <<<"$existing_bind_hosts"
    fi

    # Remove the existing bind_hosts section
    sed -i '/bind_hosts:/,/[^ ]/d' $ADGUARD_CONFIG

    # Add the new bind_hosts section
    sed -i "/dns:/a\  bind_hosts:\n    $new_bind_hosts" $ADGUARD_CONFIG

    log "AdGuard Home configuration updated."
}

# Function to restart AdGuard Home service
restart_adguard() {
    log "Checking AdGuard Home service status..."
    if systemctl is-active --quiet AdGuardHome; then
        log "AdGuard Home service is already running. Restarting."
        execute_command "systemctl restart AdGuardHome"
        log "AdGuard Home service restarted."
    else
        log "AdGuard Home service is not running. Starting."
        execute_command "systemctl start AdGuardHome"
        log "AdGuard Home service started."
    fi
}

# Function to configure iptables
configure_iptables() {
    log "Configuring iptables..."

    local private_ranges=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

    for range in "${private_ranges[@]}"; do
        add_iptables_rule INPUT "-p udp --dport 53 -s $range -j ACCEPT"
        add_iptables_rule INPUT "-p tcp --dport 53 -s $range -j ACCEPT"
        add_iptables_rule INPUT "-p tcp --dport 80 -s $range -j ACCEPT"
    done

    # Allow DNS traffic from specific IP addresses
    for ip in "${SPECIFIC_IPS[@]}"; do
        rule_exists INPUT -p udp --dport 53 -s $ip -j ACCEPT || iptables -A INPUT -p udp --dport 53 -s $ip -j ACCEPT
        rule_exists INPUT -p tcp --dport 53 -s $ip -j ACCEPT || iptables -A INPUT -p tcp -s $ip --dport 53 -j ACCEPT
    done

    # Allow traffic to and from the Wi-Fi access point
    rule_exists INPUT -s $WIFI_AP_IP -j ACCEPT || iptables -A INPUT -s $WIFI_AP_IP -j ACCEPT
    rule_exists OUTPUT -d $WIFI_AP_IP -j ACCEPT || iptables -A OUTPUT -d $WIFI_AP_IP -j ACCEPT

    add_iptables_rule INPUT "-p udp --dport 53 -s 0.0.0.0/0 -j DROP"
    add_iptables_rule INPUT "-p tcp --dport 53 -s 0.0.0.0/0 -j DROP"

    execute_command "netfilter-persistent save"
    log "iptables configured and rules saved."
}

# Function to add ufw rules
add_ufw_rule() {
    local rule=$1
    ufw status | grep -q "$rule" || ufw $rule
}

# Function to configure ufw
configure_ufw() {
    log "Configuring ufw..."

    local private_ranges=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

    for range in "${private_ranges[@]}"; do
        add_ufw_rule "allow from $range to any port 53"
        add_ufw_rule "allow from $range to any port 80"
        add_ufw_rule "allow from $range"
    done

    # Allow DNS traffic from specific IP addresses
    for ip in "${SPECIFIC_IPS[@]}"; do
        ufw status | grep -q "ALLOW IN $ip to any port 53" || ufw allow from $ip to any port 53
    done

    add_ufw_rule "allow from $WIFI_AP_IP"
    add_ufw_rule "allow to $WIFI_AP_IP"
    add_ufw_rule "deny 53"
    add_ufw_rule "allow ssh"

    log "Configuring Cloudflare IPs for HTTPS and reverse proxy..."
    execute_command "wget $CLOUDFLARE_IPS_V4_URL -O /tmp/ips-v4"
    execute_command "wget $CLOUDFLARE_IPS_V6_URL -O /tmp/ips-v6"

    while read -r cfip; do
        add_ufw_rule "allow proto tcp from $cfip to any port 443"
    done </tmp/ips-v4

    while read -r cfip; do
        add_ufw_rule "allow proto tcp from $cfip to any port 443"
    done </tmp/ips-v6

    add_ufw_rule "allow proto tcp from $REVERSE_PROXY_IP to any port 443"

    for proto in "tcp" "udp"; do
        add_ufw_rule "allow proto $proto from $CLOUDFLARE_TUNNEL_IP to any port 443"
    done

    log "Configuring Cloudflare Tunnel IPs..."
    for ip in "${TUNNEL_IPS_V4[@]}"; do
        for proto in "tcp" "udp"; do
            add_ufw_rule "allow proto $proto from $ip to any port 7844"
        done
    done

    for ip in "${TUNNEL_IPS_V6[@]}"; do
        for proto in "tcp" "udp"; do
            add_ufw_rule "allow proto $proto from $ip to any port 7844"
        done
    done

    for ip in "${OPTIONAL_IPS_V4[@]}"; do
        add_ufw_rule "allow proto tcp from $ip to any port 443"
    done

    for ip in "${OPTIONAL_IPS_V6[@]}"; do
        add_ufw_rule "allow proto tcp from $ip to any port 443"
    done

    # Allow HTTPS traffic from specific IP addresses and resolved domain IPs
    for ip in "${SPECIFIC_IPS[@]}" $DOMAIN_IPS; do
        ufw status | grep -q "ALLOW IN $ip to any port 443" || ufw allow proto tcp from $ip to any port 443
    done

    execute_command "ufw reload"
    execute_command "ufw enable"
    log "ufw configured and enabled."
}

# Function to reapply restrictive DNS rules
reapply_dns_restrictions() {
    log "Reapplying restrictive DNS rules..."
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null
    configure_iptables
    log "Restrictive DNS rules reapplied."
}

# Main script execution
main() {
    cp /etc/resolv.conf $BACKUP_RESOLV_CONF
    set_temporary_dns
    allow_dns_traffic
    install_packages
    reapply_dns_restrictions
    resolve_domain_ips
    configure_iptables
    configure_ufw
    update_adguard_config
    restart_adguard
    restore_original_dns
    log "Configuration complete. Your AdGuard Home server should now only respond to DNS queries from local networks, allow SSH, and HTTPS traffic from Cloudflare IPs, your reverse proxy, and your Cloudflare Tunnel server. Cloudflare Tunnel configuration has also been applied."
}

main
