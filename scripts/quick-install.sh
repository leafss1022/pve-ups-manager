#!/bin/bash
# PVE UPS Manager - Quick install script
# Run: bash <(curl -sL https://raw.githubusercontent.com/leafss1022/pve-ups-manager/main/scripts/quick-install.sh)

set -e

echo "=== PVE UPS Manager One-Click Deployment ==="
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Fix Debian Bullseye backports issue
OS_RELEASE=$(cat /etc/os-release 2>/dev/null | grep "^VESSION_CODENAME=" | cut -d= -f2)
if [ "$OS_RELEASE" = "bullseye" ]; then
  sed -i 's/^deb.*bullseye-backports/#.&or/etc/apt/sources.list 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/bullseye-backports.list 2>/dev/null || true
fi

# Install Node.js 20.x and npm via NodeSource
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Installing Node.js 20.x and npm..."
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1 || true
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y nodejs >/dev/null 2>&1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "Installing npm..."
  apt-get install -y npm >/dev/null 2>&1 || { curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1; apt-get install -y nodejs >/dev/null 2>&1; }
fi

echo "Node.js: $(node --version)"
echo "npm: $(npm --version 2>/dev/null)"
echo ""
echo "Downloading project..."
cd /opt
if [ -d pve-ups-manager ]; then
  cd pve-ups-manager && git pull
else
  git clone https://github.com/leafss1022/pve-ups-manager.git
  cd pve-ups-manager
fi

echo ""
echo "Installing dependencies..."
cd /opt/pve-ups-manager/backend && npm install --production

echo ""
read -p "Install NUT tools? (y/n): " install_nut
if [ "$install_nut" = "y" ]; then
  cd /opt/pve-ups-manager
  bash scripts/install-nut.sh

fi

echo ""
echo "Creating system service..."
cat > /etc/systemd/system/pve-ups-manager.service << 'EOF'
[Unit]
Description=PVE UPS Manager
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/pve-ups-manager/backend
ExecStart=/usr/bin/node /opt/pve-ups-manager/backend/app.js
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pve-ups-manager
systemctl start pve-ups-manager

echo ""
echo "=== Deployment Complete! ==="
echo "Access URL: http://$(hostname -I 2>/dev/null | awk '{print $1}'):3456"
echo "Manage: systemctl status pve-ups-manager"
echo "Logs: journalctl -u pve-ups-manager -f"
