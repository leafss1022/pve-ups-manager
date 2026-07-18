#!/bin/bash
# PVE UPS Manager - Quick install script

set -e

echo "=== PVE UPS Manager 一键部署 ==="
echo ""

# Install Node.js 20.x via NodeSource
if ! command -v node &> /dev/null || [ "$(node -v | cut -d'.' -f1 | tr -d 'v')" -lt 18 ]; then
    echo "正在安装 Node.js 20.x..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Ensure npm is installed
if ! command -v npm &> /dev/null; then
    echo "正在安装 npm..."
    apt-get install -y npm
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
echo "访问地址: http://$(hostname -I | awk '{print $1}'):3456"
echo "管理命令: systemctl status pve-ups-manager"
echo "日志查看: journalctl -u pve-ups-manager -f"
echo ""
echo "如需安装 NUT: bash /opt/pve-ups-manager/scripts/install-nut.sh"
