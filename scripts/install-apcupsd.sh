#!/bin/bash
# PVE UPS Manager - apcupsd Installation Script
# Run on Proxmox VE host

set -e

echo "=== PVE UPS Manager: apcupsd Installation ==="

# Check if running on PVE
if [ ! -f /etc/pve/version ]; then
    echo "Warning: This does not appear to be a Proxmox VE host"
    read -p "Continue anyway? [y/N] " confirm
    if [ "$confirm" != "y" ]; then exit 1; fi
fi

# Install apcupsd
echo "Installing apcupsd..."
apt-get update
apt-get install -y apcupsd

# Backup original config
backup_dir="/etc/apcupsd/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p $backup_dir
[ -f /etc/apcupsd/apcupsd.conf ] && cp /etc/apcupsd/apcupsd.conf $backup_dir/
echo "Backup saved to $backup_dir"

# Configure apcupsd to call our shutdown script on power failure
cat > /etc/apcupsd/apccontrol << 'EOF'
#!/bin/sh
# PVE UPS Manager - apcupsd control script
# Calls pve-ups-shutdown on power failure events

case "$1" in
    powerout|battlow|timeout)
        logger "apcupsd: UPS event $1 detected, initiating PVE safe shutdown"
        /usr/local/bin/pve-ups-shutdown
        ;;
esac
exec /etc/apcupsd/apccontrol.real "$@"
EOF
chmod +x /etc/apcupsd/apccontrol

# Ensure apcupsd is enabled
systemctl enable apcupsd 2>/dev/null || true

echo ""
echo "=== Installation Complete ==="
echo "Next steps:"
echo "  1. Edit /etc/apcupsd/apcupsd.conf - set UPSCABLE, UPSTYPE, DEVICE"
echo "  2. Set BATTERYLEVEL and MINUTES for auto-shutdown thresholds"
echo "  3. Start apcupsd: systemctl start apcupsd"
echo "  4. Test: apcaccess"
echo ""
echo "Or use the PVE UPS Manager web UI to configure remotely."
