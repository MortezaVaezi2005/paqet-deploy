#!/bin/bash
# Auto-generated Paqet Client Script for Linux/Mac
# SERVER_IP: {{SERVER_IP}}
# PORT: {{PAQET_PORT}}
# VERSION: {{PAQET_VERSION}}

set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Paqet Client Setup${NC}"

# Check if already installed
if [ -f "paqet" ]; then
    if [ -f "client.yaml" ]; then
        echo -e "${GREEN}Paqet already installed and configured. Starting...${NC}"
        ./paqet run -c client.yaml
        exit 0
    else
        echo -e "${GREEN}Paqet binary found but configuration missing. Skipping download...${NC}"
    fi
else
    # Only download if binary is missing
    # 2. Download Paqet Client
    VERSION="{{PAQET_VERSION}}"
    echo "Downloading Paqet Client ($VERSION)..."
    URL="https://github.com/hanselime/paqet/releases/download/$VERSION/paqet-linux-amd64-$VERSION.tar.gz"
    wget -q --show-progress "$URL" -O paqet.tar.gz
    tar -xvf paqet.tar.gz
    # Handle name variation if needed, or assume paqet_linux_amd64
    if [ -f "paqet_linux_amd64" ]; then
        mv paqet_linux_amd64 paqet
        chmod +x paqet
    else
        # heuristic find
        BIN=$(tar -tf paqet.tar.gz | head -n 1)
        mv "$BIN" paqet
        chmod +x paqet
    fi
    rm paqet.tar.gz
fi

# 3. Install yq (portable binary)
echo "Downloading yq for safe YAML editing..."
# Determine architecture for yq
ARCH="amd64" # assuming amd64 for now
wget -q "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$ARCH" -O yq
chmod +x yq

# 4. Configure Client
mkdir -p client-config

# Generate basic client.yaml if it doesn't exist
# We construct a minimal valid client yaml using yq from scratch to be safe
echo "role: client" > client.yaml
./yq -i '.log.level = "info"' client.yaml
./yq -i '.transport.protocol = "kcp"' client.yaml
./yq -i '.transport.kcp.mode = "fast"' client.yaml

echo -e "${GREEN}Configuration Setup${NC}"

# Ask for Local Port
read -p "Enter Local Listen Port (default: 1080): " LOCAL_PORT
LOCAL_PORT=${LOCAL_PORT:-1080}

# Ask for SOCKS Authentication
read -p "Do you want to enable SOCKS5 authentication? (y/N): " AUTH_ENABLE
AUTH_USER=""
AUTH_PASS=""
if [[ "$AUTH_ENABLE" =~ ^[Yy]$ ]]; then
    read -p "Enter Username: " AUTH_USER
    read -p "Enter Password: " AUTH_PASS
fi

# Apply changes using yq
echo "Applying configuration..."

# SERVER CONFIGS (Injected)
./yq -i '.network.ipv4.addr = "{{SERVER_IP}}:{{PAQET_PORT}}"' client.yaml
./yq -i '.transport.kcp.key = "{{SECRET_KEY}}"' client.yaml

# LOCAL CONFIGS (User Input)
./yq -i '.listen.addr = ":'"$LOCAL_PORT"'"' client.yaml

# Configure SOCKS5 Auth if enabled
if [ -n "$AUTH_USER" ]; then
    ./yq -i '.socks.user = "'"$AUTH_USER"'"' client.yaml
    ./yq -i '.socks.pass = "'"$AUTH_PASS"'"' client.yaml
else
    ./yq -i 'del(.socks.user)' client.yaml
    ./yq -i 'del(.socks.pass)' client.yaml
fi

echo -e "${GREEN}Starting Paqet Client...${NC}"
# Check if sudo is needed/available for running (usually not needed for high ports, but keeps consistent)
./paqet run -c client.yaml
