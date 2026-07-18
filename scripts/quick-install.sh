#!/bin/bash
# PVE UPS Manager - Quick install script
# Run: bash <(curl -sL https://raw.githubusercontent.com/leafss1022/pve-ups-manager/main/scripts/quick-install.sh)

set -e

echo "=== PVE UPS Manager 一键部署 ==="
echo ""

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "正在安装 Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

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

# Install NUT
echo ""
echo "是否安装 NUT 工具？(y/n)"
read -p "> " install_nut
if [ "$install_nut" = "y" ]; then
    cd /opt/pve-ups-manager
    bash scripts/install-nut.sh
fi

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

echo ""
echo "=== 部署完成！ ==="
echo "访问地址: http://$(hostname -I | awk "{print \$1}"):3456"
echo "管理命令: systemctl status pve-ups-manager"
echo "日志查看: journalctl -u pve-ups-manager -f"