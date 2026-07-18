#!/bin/bash
# PVE UPS Manager - Quick install script v0.4.0
set -eo pipefail 2>/dev/null || set -e
INSTALL_DIR="/opt/pve-ups-manager"
SCRIPT_URL="https://raw.githubusercontent.com/leafss1022/pve-ups-manager/main/scripts/quick-install.sh"
REPO_URL="https://github.com/leafss1022/pve-ups-manager.git"

echo "=== PVE UPS Manager Installer (v0.4.0) ==="
echo ""

# Self-reexec: if running from pipe
set +e
if [[ "$0" == /dev/fd/* ]] || [[ "$0" == "/dev/stdin" ]] || [[ -z "$BASH_SOURCE" ]]; then
  echo "[INFO] Running from pipe - downloading latest script..."
  if command -v mktemp >/dev/null 2>&1; then
    TMP_SCRIPT=$(mktemp /tmp/pve-ups-install.XXXXXX.sh 2>/dev/null)
  else
    TMP_SCRIPT="/tmp/pve-ups-install-$$.sh"
  fi
  if [ -n "$TMP_SCRIPT" ] && curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null; then
    chmod +x "$TMP_SCRIPT"
    exec bash "$TMP_SCRIPT"
  else
    echo "[WARN] Cannot download latest script, using current version..."
  fi
fi
set -e

has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_nodejs() {
  echo "[INFO] Installing Node.js 20.x ..."
  echo ""
  # Method 1: NodeSource
  if has_cmd apt-get; then
    echo "  [1/3] Trying NodeSource apt repository..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y ca-certificates curl gnupg 2>/dev/null || true
    mkdir -p /etc/apt/keyrings 2>/dev/null
    if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null; then
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
      apt-get update -qq 2>/dev/null || true
      apt-get install -y nodejs 2>/dev/null && echo "  [OK] NodeSource installation successful" && return 0 || true
    fi
    echo "  [FAIL] NodeSource failed"
  fi
  # Method 2: Binary download
  echo "  [2/3] Trying direct Node.js binary download..."
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) NODE_ARCH="linux-x64" ;;
    aarch64|arm64) NODE_ARCH="linux-arm64" ;;
    *) echo "  [FAIL] Unsupported arch: $ARCH"; return 1 ;;
  esac
  NODE_VERSION="v20.18.0"
  NODE_TAR="node-${NODE_VERSION}-${NODE_ARCH}.tar.xz"
  TMP_DIR=$(mktemp -d)
  if curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_TAR}" -o "$TMP_DIR/$NODE_TAR" 2>/dev/null; then
    tar -xf "$TMP_DIR/$NODE_TAR" -C /usr/local --strip-components=1 2>/dev/null
    rm -rf "$TMP_DIR"
    echo "  [OK] Binary installation successful" && return 0
  fi
  rm -rf "$TMP_DIR"
  echo "  [FAIL] Binary download failed"
  # Method 3: nvm
  echo "  [3/3] Trying nvm installation..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>/dev/null | bash 2>/dev/null || true
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  if nvm install 20 2>/dev/null && nvm use 20 2>/dev/null; then
    NODE_PATH=$(which node 2>/dev/null)
    [ -n "$NODE_PATH" ] && ln -sf "$NODE_PATH" /usr/local/bin/node
    echo "  [OK] nvm installation successful" && return 0
  fi
  echo "  [FAIL] nvm installation failed"
  return 1
}

# Check existing Node.js
HAVE_NODE=false
if has_cmd node; then
  NODE_MAJOR=$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)
  if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
    HAVE_NODE=true
    echo "[OK] Node.js $(node -v) detected"
  else
    echo "[INFO] Node.js $(node -v) too old (need 18+), upgrading..."
  fi
fi

if [ "$HAVE_NODE" = false ]; then
  install_nodejs || {
    echo "[ERROR] Node.js installation failed"
    echo "Install manually: curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
    exit 1
  }
fi

if ! has_cmd node; then echo "[ERROR] node not found"; exit 1; fi
if ! has_cmd npm; then
  if has_cmd apt-get; then apt-get install -y npm 2>/dev/null || true; fi
  if ! has_cmd npm; then echo "[ERROR] npm not found"; exit 1; fi
fi

echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"
echo ""

# Download/update project
echo "[INFO] Downloading project..."
cd /opt
if [ -d pve-ups-manager ]; then
  cd pve-ups-manager
  git fetch --all 2>/dev/null || true
  git reset --hard origin/main 2>/dev/null || git pull --ff-only 2>/dev/null || true
else
  git clone "$REPO_URL"
  cd pve-ups-manager
fi
echo "  [OK] Project code updated"

# Install backend dependencies
echo "[INFO] Installing backend dependencies..."
cd backend
rm -rf node_modules 2>/dev/null || true
npm install --production 2>&1 | tail -5
[ -d node_modules ] || { echo "[ERROR] Dependency install failed"; exit 1; }
echo "  [OK] Dependencies installed"

NODE_BIN=$(which node)

# Create systemd service
echo "[INFO] Creating system service..."
cat > /etc/systemd/system/pve-ups-manager.service << EOF
[Unit]
Description=PVE UPS Manager
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/backend
ExecStart=${NODE_BIN} ${INSTALL_DIR}/backend/app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/root/.nvm/versions/node/$(node -v)/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-ups-manager 2>/dev/null || true
systemctl restart pve-ups-manager

# Wait and check health
echo "[INFO] Waiting for service to start..."
sleep 3
SERVICE_OK=false
for i in 1 2 3 4 5; do
  if systemctl is-active --quiet pve-ups-manager && curl -sf --max-time 3 "http://localhost:13456/api/system/info" >/dev/null 2>&1; then
    SERVICE_OK=true; break
  fi
  echo "  Waiting... ($i/5)"; sleep 2
done

if [ "$SERVICE_OK" = true ]; then
  HOST_IP=$(hostname -I 2>/dev/null | awk "{print \$1}")
  echo "=== Deployment Successful! ==="
  echo "  Access: http://${HOST_IP:-<server-ip>}:13456"
  echo "  Status: systemctl status pve-ups-manager"
  echo "  Uninstall: bash /opt/pve-ups-manager/scripts/uninstall.sh"
  echo "  Version: v0.4.0"
else
  echo "=== Deployment completed, but service may not be running ==="
  echo "  Check logs: journalctl -u pve-ups-manager -n 30 --no-pager"
  echo "  Manual test: cd /opt/pve-ups-manager/backend && node app.js"
fi
