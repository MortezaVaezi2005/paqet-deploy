#!/bin/bash

# Paqet Management Script (paqet-deploy)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_FILE="/etc/paqet/server.yaml"
SERVICE_NAME="paqet"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Please run as root.${NC}"
        exit 1
    fi
}

get_current_port() {
    if [ -f "$CONFIG_FILE" ]; then
        # Extract port from listen addr (e.g., ":443" -> "443")
        grep "addr: \":" "$CONFIG_FILE" | head -n 1 | awk -F':' '{print $3}' | tr -d '"' | tr -d ' '
    else
        echo ""
    fi
}

view_logs() {
    echo -e "${GREEN}Following logs for $SERVICE_NAME (Press Ctrl+C to exit)...${NC}"
    journalctl -u $SERVICE_NAME -f
}

change_port() {
    OLD_PORT=$(get_current_port)
    
    if [ -z "$OLD_PORT" ]; then
        echo -e "${RED}[ERROR] Could not detect current port from config.${NC}"
        return
    fi
    
    echo -e "${YELLOW}Current Port: $OLD_PORT${NC}"
    read -p "Enter new port: " NEW_PORT
    
    if [ -z "$NEW_PORT" ] || ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid port.${NC}"
        return
    fi
    
    echo -e "${GREEN}Updating configuration...${NC}"
    
    # Update config file using sed
    sed -i "s/addr: \":$OLD_PORT\"/addr: \":$NEW_PORT\"/g" "$CONFIG_FILE"
    # Also need to update the ipv4 addr line if it contains the port
    # The install script generates ipv4 addr like "IP:PORT"
    # We can try to replace the port in that line too
    sed -i "s/:$OLD_PORT\"/:$NEW_PORT\"/g" "$CONFIG_FILE" ## This might be risky if IP has same numbers, but usually safe for :PORT pattern within quotes if format matches install.sh
    
    echo -e "${GREEN}Updating Firewall rules...${NC}"
    
    # Remove old rules
    iptables -t raw -D PREROUTING -p tcp --dport "$OLD_PORT" -j NOTRACK 2>/dev/null
    iptables -t raw -D OUTPUT -p tcp --sport "$OLD_PORT" -j NOTRACK 2>/dev/null
    iptables -t mangle -D OUTPUT -p tcp --sport "$OLD_PORT" --tcp-flags RST RST -j DROP 2>/dev/null
    ufw delete allow "$OLD_PORT/tcp" >/dev/null 2>&1
    
    # Add new rules
    iptables -t raw -A PREROUTING -p tcp --dport "$NEW_PORT" -j NOTRACK
    iptables -t raw -A OUTPUT -p tcp --sport "$NEW_PORT" -j NOTRACK
    iptables -t mangle -A OUTPUT -p tcp --sport "$NEW_PORT" --tcp-flags RST RST -j DROP
    ufw allow "$NEW_PORT/tcp" >/dev/null 2>&1
    
    netfilter-persistent save
    
    echo -e "${GREEN}Restarting service...${NC}"
    systemctl restart $SERVICE_NAME
    
    echo -e "${GREEN}Port changed from $OLD_PORT to $NEW_PORT successfully.${NC}"
}

uninstall_paqet() {
    echo -e "${RED}WARNING: This will remove Paqet and all its configuration.${NC}"
    read -p "Are you sure? (y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Aborted."
        return
    fi
    
    echo -e "${YELLOW}Stopping service...${NC}"
    systemctl stop $SERVICE_NAME
    systemctl disable $SERVICE_NAME
    
    CURRENT_PORT=$(get_current_port)
    if [ -n "$CURRENT_PORT" ]; then
        echo -e "${YELLOW}Cleaning up firewall rules for port $CURRENT_PORT...${NC}"
        iptables -t raw -D PREROUTING -p tcp --dport "$CURRENT_PORT" -j NOTRACK 2>/dev/null
        iptables -t raw -D OUTPUT -p tcp --sport "$CURRENT_PORT" -j NOTRACK 2>/dev/null
        iptables -t mangle -D OUTPUT -p tcp --sport "$CURRENT_PORT" --tcp-flags RST RST -j DROP 2>/dev/null
        ufw delete allow "$CURRENT_PORT/tcp" >/dev/null 2>&1
        netfilter-persistent save
    fi
    
    echo -e "${YELLOW}Removing files...${NC}"
    rm -f /usr/local/bin/paqet
    rm -f /etc/systemd/system/paqet.service
    rm -rf /etc/paqet
    rm -f /usr/local/bin/paqet-deploy
    
    systemctl daemon-reload
    
    echo -e "${GREEN}Paqet uninstalled successfully.${NC}"
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
    
    case $OPTION in
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
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    echo ""
    read -p "Press Enter to continue..."
done
