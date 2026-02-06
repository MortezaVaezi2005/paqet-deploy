#!/bin/bash

# Paqet Server Installer
# This script automates the installation and configuration of Paqet Server.

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for root
if [ "$EUID" -ne 0 ]; then
  log_error "Please run as root"
  exit 1
fi

log_info "Starting Paqet Server Installation..."

# 1. Install Prerequisites
log_info "Installing prerequisites..."
apt-get update -y
apt-get install -y wget curl tar jq libpcap-dev iptables-persistent net-tools

# Error Handling Function with AI Support
handle_error() {
    local exit_code=$1
    local command="${BASH_COMMAND}"
    local error_msg=$(tail -n 10 /tmp/paqet_install.log 2>/dev/null) # Assuming we log to file, or just generic message
    
    echo -e "${RED}[ERROR] Command failed with exit code $exit_code${NC}"
    echo -e "${RED}[ERROR] Failed command: $command${NC}"
    
    echo -e "${YELLOW}Consulting AI for help...${NC}"
    
    # Construct Prompt
    PROMPT="I am a Bash script installer for a server software called 'Paqet'. The script failed at this command: '$command'. The exit code was $exit_code. System info: $(uname -a). Please explain why this might happen and provide a specific fix command for the user (Ubuntu/Debian). Keep it short."
    
    # URL Encode Prompt (simple approximation for bash)
    ENCODED_PROMPT=$(echo "$PROMPT" | jq -sRr @uri)
    
    # Call AI
    AI_RESPONSE=$(curl -s "https://text.pollinations.ai/$ENCODED_PROMPT")
    
    echo -e "${GREEN}--- AI Suggestion ---${NC}"
    echo -e "$AI_RESPONSE"
    echo -e "${GREEN}---------------------${NC}"
    
    exit $exit_code
}

# Trap errors
# Note: trap logic can be complex with set -e. 
# proper way: set -e and trap 'handle_error $?' ERR
trap 'handle_error $?' ERR

# 2. Get User Input
# Port
read -p "Enter the port for Paqet server (default: 443): " PAQET_PORT
PAQET_PORT=${PAQET_PORT:-443}

# Install Location
read -p "Enter install location (default: /opt/paqet): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/paqet}

# 3. System Discovery
log_info "Discovering system information..."

# Public IP
PUBLIC_IP=$(curl -s https://api.ipify.org)
if [ -z "$PUBLIC_IP" ]; then
    log_warn "Could not detect public IP automatically. Please enter it manually."
    read -p "Public IP: " PUBLIC_IP
fi
log_info "Detected Public IP: $PUBLIC_IP"

# Interface and Gateway
DEFAULT_ROUTE=$(ip route show default | awk '/default/ {print $0}')
INTERFACE=$(echo "$DEFAULT_ROUTE" | awk '/dev/ {print $5}')
GATEWAY_IP=$(echo "$DEFAULT_ROUTE" | awk '/via/ {print $3}')

log_info "Detected Interface: $INTERFACE"
log_info "Detected Gateway IP: $GATEWAY_IP"

# Gateway MAC
# Gateway MAC
log_info "Detecting Gateway MAC..."
# Try to ping gateway first to populate ARP table
ping -c 3 -W 1 "$GATEWAY_IP" > /dev/null 2>&1 || true

# Method 1: ip neigh (Look specifically for lladdr tag)
GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" dev "$INTERFACE" | awk '/lladdr/ { for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1) }')

# Method 2: arp command (fallback)
if [[ -z "$GATEWAY_MAC" ]]; then
    if command -v arp >/dev/null; then
        GATEWAY_MAC=$(arp -an | grep "($GATEWAY_IP)" | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | head -n 1)
    fi
fi

# Method 3: /proc/net/arp (fallback)
if [[ -z "$GATEWAY_MAC" ]]; then
    GATEWAY_MAC=$(awk -v ip="$GATEWAY_IP" '$1==ip {print $4}' /proc/net/arp)
fi

# Validation
if [[ -z "$GATEWAY_MAC" ]] || [[ "$GATEWAY_MAC" == "00:00:00:00:00:00" ]]; then
    log_error "Could not detect Gateway MAC address."
    log_warn "Possible reasons:"
    log_warn "1. Gateway is not reachable (check network)."
    log_warn "2. Gateway ignores ping (ICMP blocked)."
    log_warn "3. Environment does not support ARP (e.g., some VPS types)."
    
    # Allow manual entry as last resort
    read -p "Enter Gateway MAC manually (or press Enter to exit): " MANUAL_MAC
    if [[ -n "$MANUAL_MAC" ]]; then
        GATEWAY_MAC="$MANUAL_MAC"
    else
        exit 1
    fi
fi

log_info "Detected Gateway MAC: $GATEWAY_MAC"

# 4. Fetch Latest Version
log_info "Fetching latest Paqet version..."
LATEST_RELEASE_URL="https://api.github.com/repos/hanselime/paqet/releases/latest"
LATEST_TAG=$(curl -s "$LATEST_RELEASE_URL" | jq -r .tag_name)

if [ "$LATEST_TAG" == "null" ] || [ -z "$LATEST_TAG" ]; then
    log_error "Failed to fetch latest version from GitHub."
    exit 1
fi

log_info "Latest version: $LATEST_TAG"

DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/${LATEST_TAG}/paqet-linux-amd64-${LATEST_TAG}.tar.gz"
FILENAME="paqet-linux-amd64-${LATEST_TAG}.tar.gz"

# 5. Download and Install
log_info "Downloading Paqet..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME"

log_info "Extracting..."
tar -xvf "$FILENAME"
# The tarball usually contains paqet_linux_amd64, handle naming variations if necessary
# Based on user input, it extracts to something like paqet_linux_amd64
EXTRACTED_FILE="paqet_linux_amd64"
if [ ! -f "$EXTRACTED_FILE" ]; then
    # Start looking for probable binary name if exact match fails
    EXTRACTED_FILE=$(tar -tf "$FILENAME" | head -n 1)
fi

log_info "Installing binary..."
mv "$EXTRACTED_FILE" /usr/local/bin/paqet
chmod +x /usr/local/bin/paqet
rm "$FILENAME"

# Symlink check for libpcap (sometimes needed)
if [ ! -f /usr/lib/x86_64-linux-gnu/libpcap.so.0.8 ]; then
    if [ -f /usr/lib/x86_64-linux-gnu/libpcap.so ]; then
        ln -s /usr/lib/x86_64-linux-gnu/libpcap.so /usr/lib/x86_64-linux-gnu/libpcap.so.0.8
    fi
fi
ldconfig

# 6. Generate Configuration
log_info "Generating configuration..."
mkdir -p /etc/paqet

# Generate Secret
SECRET_KEY=$(paqet secret)

cat > /etc/paqet/server.yaml <<EOF
# Paqet Server Configuration - Auto-generated
role: "server"

log:
  level: "info"

listen:
  addr: ":$PAQET_PORT"

network:
  interface: "$INTERFACE"
  
  ipv4:
    addr: "$PUBLIC_IP:$PAQET_PORT"
    router_mac: "$GATEWAY_MAC"

  # IPv6 configuration omitted manually for now as per minimal requirement, 
  # can be added if detecting IPv6

  tcp:
    local_flag: ["PA"]

transport:
  protocol: "kcp"
  conn: 1
  kcp:
    mode: "fast"
    key: "$SECRET_KEY"

# Firewall Configuration Note:
# Rules are applied via iptables below.
EOF

log_info "Configuration saved to /etc/paqet/server.yaml"

# 7. Configure Network/Firewall
log_info "Configuring Firewall..."

# Open port
ufw allow "$PAQET_PORT/tcp" || true

# Paqet specific iptables rules
# Clean old rules if they exist (simple cleanup might be tricky without exact match, sticking to adding for now)
iptables -t raw -A PREROUTING -p tcp --dport "$PAQET_PORT" -j NOTRACK
iptables -t raw -A OUTPUT -p tcp --sport "$PAQET_PORT" -j NOTRACK
iptables -t mangle -A OUTPUT -p tcp --sport "$PAQET_PORT" --tcp-flags RST RST -j DROP

netfilter-persistent save

# 8. Create Systemd Service
log_info "Creating systemd service..."

cat > /etc/systemd/system/paqet.service <<EOF
[Unit]
Description=Paqet Server
After=network.target

[Service]
ExecStart=/usr/local/bin/paqet run -c /etc/paqet/server.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet
systemctl start paqet




# 9. Client Distribution System
log_info "Setting up Client Distribution System..."
DIST_DIR="/opt/paqet-distribution"
TEMPLATE_DIR="/etc/paqet/templates"
mkdir -p "$DIST_DIR"
mkdir -p "$TEMPLATE_DIR"

# Install pure-python http server
if ! command -v python3 &> /dev/null; then
    log_warn "Python3 not found. Installing..."
    apt-get install -y python3
fi

# Detect LATEST_TAG again (safeguard)
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG=$(cat /tmp/paqet_latest_version 2>/dev/null || echo "v1.0.0-alpha.13")
else
    echo "$LATEST_TAG" > /tmp/paqet_latest_version
fi

# Determine source of templates
# If running from local dir with templates foler
if [ -d "templates" ]; then
    cp templates/connect.sh "$TEMPLATE_DIR/connect.sh"
    cp templates/connect.bat "$TEMPLATE_DIR/connect.bat"
else
    log_warn "Templates directory not found locally. Client scripts might be missing."
    # Fallback or error handling could go here, but assuming user follows instructions
fi

# Function to generate client scripts from templates
generate_client_scripts() {
    local TARGET_DIR=$1
    local SRC_DIR=$2
    local IP=$3
    local PORT=$4
    local SECRET=$5
    local VER=$6

    log_info "Generating client scripts for Version: $VER"

    # Process connect.sh
    if [ -f "$SRC_DIR/connect.sh" ]; then
        sed -e "s|{{SERVER_IP}}|$IP|g" \
            -e "s|{{PAQET_PORT}}|$PORT|g" \
            -e "s|{{SECRET_KEY}}|$SECRET|g" \
            -e "s|{{PAQET_VERSION}}|$VER|g" \
            "$SRC_DIR/connect.sh" > "$TARGET_DIR/connect.sh"
        chmod +x "$TARGET_DIR/connect.sh"
    fi

    # Process connect.bat
     if [ -f "$SRC_DIR/connect.bat" ]; then
        sed -e "s|{{SERVER_IP}}|$IP|g" \
            -e "s|{{PAQET_PORT}}|$PORT|g" \
            -e "s|{{SECRET_KEY}}|$SECRET|g" \
            -e "s|{{PAQET_VERSION}}|$VER|g" \
            "$SRC_DIR/connect.bat" > "$TARGET_DIR/connect.bat"
    fi
}

# Generate initial scripts
generate_client_scripts "$DIST_DIR" "$TEMPLATE_DIR" "$PUBLIC_IP" "$PAQET_PORT" "$SECRET_KEY" "$LATEST_TAG"

# Create Distribution Service
log_info "Creating Distribution Service on port 2026..."
cat > /etc/systemd/system/paqet-distribution.service <<EOF
[Unit]
Description=Paqet Client Distribution Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 2026 --directory $DIST_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet-distribution
systemctl start paqet-distribution
ufw allow 2026/tcp || true

log_info "Client Distribution System Ready!"
log_info "Linux/Mac Install: curl http://$PUBLIC_IP:2026/connect.sh | bash"
log_info "Windows Install:   http://$PUBLIC_IP:2026/connect.bat"


# 10. Install Management Script (paqet-deploy)
log_info "Installing management script..."

cat > /usr/local/bin/paqet-deploy <<SHELL
#!/bin/bash
# Paqet Management Script

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$INSTALL_DIR"
CONFIG_FILE="\$INSTALL_DIR/server.yaml"
SERVICE_NAME="paqet"

# Error Handling with AI
handle_error() {
    local exit_code=\$1
    local command="\${BASH_COMMAND}"
    
    echo -e "\${RED}[ERROR] Command failed with exit code \$exit_code\${NC}"
    echo -e "\${RED}[ERROR] Failed command: \$command\${NC}"
    echo -e "\${YELLOW}Consulting AI for help...\${NC}"
    PROMPT="I am a Paqet manager script. Error at '\$command' (exit \$exit_code). Sys: \$(uname -a). Explain and fix."
    ENCODED_PROMPT=\$(echo "\$PROMPT" | jq -sRr @uri)
    AI_RESPONSE=\$(curl -s "https://text.pollinations.ai/\$ENCODED_PROMPT")
    echo -e "\${GREEN}--- AI Suggestion ---\${NC}"
    echo -e "\$AI_RESPONSE"
    echo -e "\${GREEN}---------------------\${NC}"
    exit \$exit_code
}
trap 'handle_error \$?' ERR

check_root() {
    if [ "\$EUID" -ne 0 ]; then
        echo -e "\${RED}[ERROR] Please run as root.\${NC}"
        exit 1
    fi
}

get_current_port() {
    if [ -f "\$CONFIG_FILE" ]; then
        grep "addr: \":" "\$CONFIG_FILE" | head -n 1 | awk -F':' '{print \$3}' | tr -d '"' | tr -d ' '
    else
        echo ""
    fi
}

view_logs() {
    echo -e "\${GREEN}Following logs for \$SERVICE_NAME (Press Ctrl+C to exit)...\${NC}"
    journalctl -u \$SERVICE_NAME -f
}

change_port() {
    OLD_PORT=\$(get_current_port)
    
    if [ -z "\$OLD_PORT" ]; then
        echo -e "\${RED}[ERROR] Could not detect current port from config.\${NC}"
        return
    fi
    
    echo -e "\${YELLOW}Current Port: \$OLD_PORT\${NC}"
    read -p "Enter new port: " NEW_PORT
    
    if [ -z "\$NEW_PORT" ] || ! [[ "\$NEW_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "\${RED}[ERROR] Invalid port.\${NC}"
        return
    fi
    
    echo -e "\${GREEN}Updating configuration...\${NC}"
    
    sed -i "s/addr: \":\$OLD_PORT\"/addr: \":\$NEW_PORT\"/g" "\$CONFIG_FILE"
    sed -i "s/:\$OLD_PORT\"/:\$NEW_PORT\"/g" "\$CONFIG_FILE"
    
    echo -e "\${GREEN}Updating Firewall rules...\${NC}"
    
    # Remove old rules
    iptables -t raw -D PREROUTING -p tcp --dport "\$OLD_PORT" -j NOTRACK 2>/dev/null
    iptables -t raw -D OUTPUT -p tcp --sport "\$OLD_PORT" -j NOTRACK 2>/dev/null
    iptables -t mangle -D OUTPUT -p tcp --sport "\$OLD_PORT" --tcp-flags RST RST -j DROP 2>/dev/null
    ufw delete allow "\$OLD_PORT/tcp" >/dev/null 2>&1
    
    # Add new rules
    iptables -t raw -A PREROUTING -p tcp --dport "\$NEW_PORT" -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport "\$NEW_PORT" -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport "\$NEW_PORT" --tcp-flags RST RST -j DROP
    ufw allow "\$NEW_PORT/tcp" >/dev/null 2>&1
    
    netfilter-persistent save
    
    echo -e "\${GREEN}Restarting service...\${NC}"
    systemctl restart \$SERVICE_NAME
    
    echo -e "\${GREEN}Port changed from \$OLD_PORT to \$NEW_PORT successfully.\${NC}"
}

uninstall_paqet() {
    echo -e "\${RED}WARNING: This will remove Paqet and all its configuration.\${NC}"
    read -p "Are you sure? (y/N): " CONFIRM
    if [[ "\$CONFIRM" != "y" && "\$CONFIRM" != "Y" ]]; then
        echo "Aborted."
        return
    fi
    
    echo -e "\${YELLOW}Stopping service...\${NC}"
    systemctl stop \$SERVICE_NAME
    systemctl disable \$SERVICE_NAME
    
    CURRENT_PORT=\$(get_current_port)
    if [ -n "\$CURRENT_PORT" ]; then
        echo -e "\${YELLOW}Cleaning up firewall rules for port \$CURRENT_PORT...\${NC}"
        iptables -t raw -D PREROUTING -p tcp --dport "\$CURRENT_PORT" -j NOTRACK 2>/dev/null
        iptables -t raw -D OUTPUT -p tcp --sport "\$CURRENT_PORT" -j NOTRACK 2>/dev/null
        iptables -t mangle -D OUTPUT -p tcp --sport "\$CURRENT_PORT" --tcp-flags RST RST -j DROP 2>/dev/null
        ufw delete allow "\$CURRENT_PORT/tcp" >/dev/null 2>&1
        netfilter-persistent save
    fi
    
    echo -e "\${YELLOW}Removing files...\${NC}"
    rm -rf "\$INSTALL_DIR"
    rm -f /etc/systemd/system/paqet.service
    rm -f /usr/local/bin/paqet-deploy
    
    systemctl daemon-reload
    
    echo -e "\${GREEN}Paqet uninstalled successfully.\${NC}"
    exit 0
}

show_menu() {
    echo "================================="
    echo "      Paqet Manager v1.0         "
    echo "================================="
    echo "1. View Logs"
    echo "2. Uninstall Paqet"
    echo "3. Change Settings (Port)"
    echo "0. Exit"
    echo "================================="
}

check_root

while true; do
    show_menu
    read -p "Select an option: " OPTION
    
    case \$OPTION in
        1)
            view_logs
            ;;
        2)
            uninstall_paqet
            ;;
        3)
            change_port
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "\${RED}Invalid option.\${NC}"
            ;;
    esac
    echo ""
    read -p "Press Enter to continue..."
done
SHELL
chmod +x /usr/local/bin/paqet-deploy
log_info "Management script installed as 'paqet-deploy'."

# 11. AI Verification Check
log_info "Waiting for service to stabilize (5 seconds)..."
sleep 5

LOG_CONTENT=$(journalctl -u paqet --no-pager -n 20)
log_info "Verifying service status with AI..."

VERIFY_PROMPT="I just installed a server service called Paqet. Here are the last 20 logs:
$LOG_CONTENT
---
Does this look like a successful startup? It should be listening on port $PAQET_PORT. Answer simply YES or NO, and why."

ENCODED_VERIFY=$(echo "$VERIFY_PROMPT" | jq -sRr @uri)
AI_VERIFY_RESPONSE=$(curl -s "https://text.pollinations.ai/$ENCODED_VERIFY")

echo -e "${GREEN}--- AI Verification Report ---${NC}"
echo -e "$AI_VERIFY_RESPONSE"
echo -e "${GREEN}------------------------------${NC}"


 # Final Summary
log_info "---------------------------------------------------"
log_info "Paqet Server & Distribution System Installed!"
log_info "---------------------------------------------------"
log_info "Server Port:   $PAQET_PORT"
log_info "Secret Key:    $SECRET_KEY"
log_info "Location:      $INSTALL_DIR"
log_info "AI Check:      See report above."
log_info "---------------------------------------------------"
log_info "To connect a client, run:"
log_info "Download Client Script: curl http://$PUBLIC_IP:2026/connect.sh | bash"
log_info "---------------------------------------------------"



log_info "Port: $PAQET_PORT"
log_info "Secret Key: $SECRET_KEY"
log_info "You can view logs with: journalctl -u paqet -f"
