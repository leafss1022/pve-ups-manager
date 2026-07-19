#!/bin/bash
# PVE UPS Manager - apcupsd Installation Script
# Run on Proxmox VE host
# Usage: bash /opt/pve-ups-manager/scripts/install-apcupsd.sh

set -eo pipefail

echo "=== PVE UPS Manager: apcupsd 安装 ==="
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

# Install apcupsd
echo "安装 apcupsd..."
apt-get update -qq
apt-get install -y apcupsd

# Backup original config
backup_dir="/etc/apcupsd/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
[ -f /etc/apcupsd/apcupsd.conf ] && cp /etc/apcupsd/apcupsd.conf "$backup_dir/"
echo "原配置已备份到 $backup_dir"

# Install shutdown hook first
SHUTDOWN_SCRIPT="$PROJECT_DIR/scripts/pve-ups-shutdown.sh"
if [ -f "$SHUTDOWN_SCRIPT" ]; then
    cp "$SHUTDOWN_SCRIPT" /usr/local/bin/pve-ups-shutdown
    chmod +x /usr/local/bin/pve-ups-shutdown
    echo "关机脚本已安装到 /usr/local/bin/pve-ups-shutdown"
else
    echo "[警告] 未找到关机脚本 $SHUTDOWN_SCRIPT"
fi

# Backup original apccontrol if not already backed up
if [ -f /etc/apcupsd/apccontrol ] && [ ! -f /etc/apcupsd/apccontrol.real ]; then
    cp /etc/apcupsd/apccontrol /etc/apcupsd/apccontrol.real
fi

# Configure apcupsd to call our shutdown script on power failure events
cat > /etc/apcupsd/apccontrol << 'APCEOF'
#!/bin/sh
# PVE UPS Manager - apcupsd control script
# Calls pve-ups-shutdown on power failure events

case "$1" in
    powerout|battlow|timeout|doshutdown)
        logger "apcupsd: UPS event $1 detected, initiating PVE safe shutdown"
        /usr/local/bin/pve-ups-shutdown
        ;;
esac

# Fall through to original apccontrol for other events
if [ -x /etc/apcupsd/apccontrol.real ]; then
    exec /etc/apcupsd/apccontrol.real "$@"
fi
APCEOF
chmod +x /etc/apcupsd/apccontrol

# Ensure apcupsd is enabled
systemctl enable apcupsd 2>/dev/null || true

echo ""
echo "=== apcupsd 安装完成 ==="
echo ""
echo "后续步骤:"
echo "  1. 编辑 /etc/apcupsd/apcupsd.conf - 设置 UPSCABLE, UPSTYPE, DEVICE"
echo "  2. 设置 BATTERYLEVEL 和 MINUTES 自动关机阈值"
echo "  3. 启动 apcupsd: systemctl start apcupsd"
echo "  4. 测试: apcaccess"
echo ""
echo "或使用 PVE UPS Manager Web 界面进行远程配置。"
