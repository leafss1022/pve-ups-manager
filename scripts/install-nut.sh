#!/bin/bash
# PVE UPS Manager - NUT Installation Script
# Run on Proxmox VE host

set -e

echo "=== PVE UPS Manager: NUT Installation ==="

# Check if running on PVE
if [ ! -f /etc/pve/version ]; then
    echo "Warning: This does not appear to be a Proxmox VE host"
    read -p "Continue anyway? [y/N] " confirm
    if [ "$confirm" != "y" ]; then exit 1; fi
fi

# Install NUT
echo "Installing NUT packages..."
apt-get update
apt-get install -y nut nut-client nut-server

# Backup original configs
backup_dir="/etc/nut/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p $backup_dir
[ -f /etc/nut/ups.conf ] && cp /etc/nut/ups.conf $backup_dir/
[ -f /etc/nut/upsd.conf ] && cp /etc/nut/upsd.conf $backup_dir/
[ -f /etc/nut/upsd.users ] && cp /etc/nut/upsd.users $backup_dir/
[ -f /etc/nut/upsmon.conf ] && cp /etc/nut/upsmon.conf $backup_dir/
echo "Backups saved to $backup_dir"

# Install shutdown hook
cp scripts/pve-ups-shutdown.sh /usr/local/bin/pve-ups-shutdown
chmod +x /usr/local/bin/pve-ups-shutdown
echo "Shutdown hook installed to /usr/local/bin/pve-ups-shutdown"

# Configure upsmon to use our shutdown script
if grep -q "^SHUTDOWNCMD" /etc/nut/upsmon.conf 2>/dev/null; then
    sed -i 's|^SHUTDOWNCMD.*|SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"|' /etc/nut/upsmon.conf
else
    echo 'SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"' >> /etc/nut/upsmon.conf
fi

# Enable and start services
systemctl enable nut-server nut-monitor 2>/dev/null || true
systemctl restart nut-server nut-monitor 2>/dev/null || true

echo ""
echo "=== Installation Complete ==="
echo "Next steps:"
echo "  1. Edit /etc/nut/ups.conf  - configure your UPS device"
echo "  2. Edit /etc/nut/upsd.conf - set LISTEN address"
echo "  3. Edit /etc/nut/upsd.users - set username/password"
echo "  4. Edit /etc/nut/upsmon.conf - verify MONITOR line"
echo "  5. Restart NUT services: systemctl restart nut-server nut-monitor"
echo "  6. Test: upsc ups@localhost"
echo ""
echo "Or use the PVE UPS Manager web UI to configure remotely."
