#!/bin/bash
# PVE UPS Manager - NUT Installation Script
# Run on Proxmox VE host
# Usage: bash /opt/pve-ups-manager/scripts/install-nut.sh

set -eo pipefail

echo "=== PVE UPS Manager: NUT 安装 ==="
echo ""

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if running on PVE
if [ ! -f /etc/pve/version ]; then
    echo "警告: 当前系统似乎不是 Proxmox VE 主机"
    if [ -t 0 ]; then
        read -p "是否继续? [y/N] " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then exit 1; fi
    else
        echo "非交互模式，继续安装..."
    fi
fi

# Install NUT
echo "安装 NUT 软件包..."
apt-get update -qq
apt-get install -y nut nut-client nut-server

# Backup original configs
backup_dir="/etc/nut/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
for f in ups.conf upsd.conf upsd.users upsmon.conf; do
    [ -f "/etc/nut/$f" ] && cp "/etc/nut/$f" "$backup_dir/"
done
echo "原配置已备份到 $backup_dir"

# Install shutdown hook
SHUTDOWN_SCRIPT="$PROJECT_DIR/scripts/pve-ups-shutdown.sh"
if [ -f "$SHUTDOWN_SCRIPT" ]; then
    cp "$SHUTDOWN_SCRIPT" /usr/local/bin/pve-ups-shutdown
    chmod +x /usr/local/bin/pve-ups-shutdown
    echo "关机脚本已安装到 /usr/local/bin/pve-ups-shutdown"
else
    echo "[警告] 未找到关机脚本 $SHUTDOWN_SCRIPT"
fi

# Configure upsmon to use our shutdown script
if [ -f /etc/nut/upsmon.conf ]; then
    if grep -q "^SHUTDOWNCMD" /etc/nut/upsmon.conf 2>/dev/null; then
        sed -i 's|^SHUTDOWNCMD.*|SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"|' /etc/nut/upsmon.conf
    else
        echo 'SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"' >> /etc/nut/upsmon.conf
    fi
else
    echo 'SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"' > /etc/nut/upsmon.conf
fi

# Enable and start services
systemctl enable nut-server nut-monitor 2>/dev/null || true
systemctl restart nut-server nut-monitor 2>/dev/null || true

echo ""
echo "=== NUT 安装完成 ==="
echo ""
echo "后续步骤:"
echo "  1. 编辑 /etc/nut/ups.conf  - 配置 UPS 设备"
echo "  2. 编辑 /etc/nut/upsd.conf - 设置监听地址"
echo "  3. 编辑 /etc/nut/upsd.users - 设置用户名/密码"
echo "  4. 编辑 /etc/nut/upsmon.conf - 确认 MONITOR 行"
echo "  5. 重启 NUT 服务: systemctl restart nut-server nut-monitor"
echo "  6. 测试: upsc ups@localhost"
echo ""
echo "或使用 PVE UPS Manager Web 界面进行远程配置。"