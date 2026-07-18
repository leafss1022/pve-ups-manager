#!/bin/bash
# PVE UPS Manager - Quick install script

set -e

echo "=== PVE UPS Manager 一键部署 ==="
echo ""

# Check if Node.js >= 18 exists
HAVE_NODE=false
if command -v node &> /dev/null; then
    NODE_MAJOR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
        HAVE_NODE=true
    fi
fi

if [ "$HAVE_NODE" = false ]; then
    echo "正在安装 Node.js 20.x (NodeSource)..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
    apt-get update -qq
    apt-get install -y nodejs
fi

echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"

# Download project
echo "正在下载项目..."
cd /opt
if [ -d pve-ups-manager ]; then
    cd pve-ups-manager && git pull
else
    git clone https://github.com/leafss1022/pve-ups-manager.git
    cd pve-ups-manager
fi

# Install dependencies
echo "正在安装依赖..."
cd backend && npm install --production

# Create systemd service
echo "创建系统服务..."
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

sleep 2

echo ""
echo "=== 部署完成！ ==="
HOST_IP=$(hostname -I | awk "{print $1}")
echo "访问地址: http://$HOST_IP:3456"
echo "管理命令: systemctl status pve-ups-manager"
echo "日志查看: journalctl -u pve-ups-manager -f"
echo ""
echo "如需安装 NUT: bash /opt/pve-ups-manager/scripts/install-nut.sh"
