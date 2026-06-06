#!/bin/bash

# Spoof Panel Installer
# Usage: bash <(curl -Ls <ANY_REPO_URL>/panel/install.sh)
#
# The script auto-detects which repository it came from, so it works
# with any fork — just change the URL in the curl command.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="/usr/local/bin"
DATA_DIR="/etc/spoof-panel"
SERVICE_NAME="spoof-panel"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║         Spoof Panel Installer            ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# ── Auto-detect repository ──
# If the user passes REPO=owner/repo as an env var, use that.
# Otherwise try to detect from the URL this script was fetched from.
# As a last resort, ask the user.
if [ -n "$REPO" ]; then
    # User explicitly set REPO env var
    :
elif [ -n "$INSTALL_REPO_URL" ]; then
    # Full URL provided — extract owner/repo
    # e.g. https://github.com/SomeUser/spoof-tunnel → SomeUser/spoof-tunnel
    REPO=$(echo "$INSTALL_REPO_URL" | sed -E 's|.*github\.com/([^/]+/[^/]+).*|\1|')
elif [ -n "$0" ] && [ "$0" != "bash" ] && [ "$0" != "/dev/stdin" ]; then
    # Try to detect from the script's own URL (when run via curl|bash)
    SCRIPT_URL="${_INSTALL_SOURCE:-}"
    if [ -z "$SCRIPT_URL" ]; then
        # Try to extract from the process command line
        SCRIPT_URL=$(cat /proc/$PPID/cmdline 2>/dev/null | tr '\0' ' ' | grep -oP 'https?://[^ ]+install\.sh' || true)
    fi
    if [ -n "$SCRIPT_URL" ]; then
        REPO=$(echo "$SCRIPT_URL" | sed -E 's|.*github\.com/([^/]+/[^/]+).*|\1|')
    fi
fi

# If still not detected, ask the user
if [ -z "$REPO" ]; then
    echo -e "${YELLOW}Could not auto-detect the repository.${NC}"
    echo -e "${YELLOW}Please enter the GitHub repo (owner/repo) or full URL:${NC}"
    echo -e "${YELLOW}Examples: ParsaKSH/spoof-tunnel  or  https://github.com/YourName/spoof-tunnel${NC}"
    read -rp "Repository: " REPO_INPUT
    # Extract owner/repo from whatever the user typed
    REPO=$(echo "$REPO_INPUT" | sed -E 's|.*github\.com/([^/]+/[^/]+).*|\1|')
    if [ -z "$REPO" ]; then
        REPO="$REPO_INPUT"
    fi
fi

# Validate REPO format (should be owner/repo)
if ! echo "$REPO" | grep -qP '^[^/]+/[^/]+$'; then
    echo -e "${RED}Invalid repository format: ${REPO}${NC}"
    echo -e "${RED}Expected: owner/repo  (e.g. ParsaKSH/spoof-tunnel)${NC}"
    exit 1
fi

echo -e "${GREEN}Using repository: ${REPO}${NC}"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
echo -e "${GREEN}Detected: ${OS}/${ARCH}${NC}"

# Get latest release
echo -e "${YELLOW}Fetching latest release from ${REPO}...${NC}"
LATEST=$(curl -s "https://api.github.com/repos/${REPO}/releases" | grep -o '"tag_name": *"v[^"]*"' | head -1 | grep -o 'v[^"]*')

if [ -z "$LATEST" ]; then
    echo -e "${YELLOW}No panel release found, using latest tag...${NC}"
    LATEST=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep -o '"tag_name": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
fi

if [ -z "$LATEST" ]; then
    echo -e "${RED}Could not find any releases in ${REPO}${NC}"
    exit 1
fi

echo -e "${GREEN}Latest version: ${LATEST}${NC}"

# Download panel binary
PANEL_URL="https://github.com/${REPO}/releases/download/${LATEST}/spoof-panel-${OS}-${ARCH}"
echo -e "${YELLOW}Downloading panel...${NC}"
curl -Lo /tmp/spoof-panel "${PANEL_URL}" || {
    echo -e "${RED}Download failed!${NC}"
    echo -e "${RED}URL: ${PANEL_URL}${NC}"
    exit 1
}
chmod +x /tmp/spoof-panel

# Download spoof binary
SPOOF_URL="https://github.com/${REPO}/releases/download/${LATEST}/spoof-${OS}-${ARCH}"
echo -e "${YELLOW}Downloading spoof tunnel...${NC}"
curl -Lo /tmp/spoof "${SPOOF_URL}" 2>/dev/null || {
    echo -e "${YELLOW}Spoof binary not in this release, will try separate...${NC}"
}

# Install
echo -e "${YELLOW}Installing...${NC}"
mkdir -p "${DATA_DIR}"
mv /tmp/spoof-panel "${INSTALL_DIR}/spoof-panel"

if [ -f /tmp/spoof ]; then
    chmod +x /tmp/spoof
    mv /tmp/spoof "${DATA_DIR}/spoof"
fi

# Stop existing service if running
systemctl stop ${SERVICE_NAME} 2>/dev/null || true

# Generate random credentials
PORT=$(shuf -i 10000-60000 -n 1)
USERNAME=$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
PASSWORD=$(head -c 100 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)

# Setup the panel (creates DB, user, port, web_path)
export SPOOF_DATA_DIR="${DATA_DIR}"

# Create the database and user directly via the binary
SETUP_OUTPUT=$(${INSTALL_DIR}/spoof-panel -setup-user "${USERNAME}" -setup-pass "${PASSWORD}" -setup-port "${PORT}" 2>/dev/null)
echo "$SETUP_OUTPUT"

# Extract web path from setup output
WEB_PATH=$(echo "$SETUP_OUTPUT" | grep -oP 'Web Path:\s+\K/\S+' || echo "")

# Create systemd service
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Spoof Panel
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/spoof-panel -port ${PORT}
Environment=SPOOF_DATA_DIR=${DATA_DIR}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl start ${SERVICE_NAME}

# Wait for startup
sleep 2

# Get server IP
SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║       Installation Complete! ✓                   ║"
echo "╠══════════════════════════════════════════════════╣"
printf "║  URL:      http://%-30s║\n" "${SERVER_IP}:${PORT}${WEB_PATH}/"
printf "║  Username: %-38s║\n" "${USERNAME}"
printf "║  Password: %-38s║\n" "${PASSWORD}"
printf "║  Web Path: %-38s║\n" "${WEB_PATH}"
printf "║  Repo:     %-38s║\n" "${REPO}"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Service: systemctl status spoof-panel            ║"
echo "║  Logs:    journalctl -u spoof-panel -f            ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}⚠  Save these credentials! They won't be shown again.${NC}"
echo ""
