#!/bin/bash
# PVE UPS Manager - apcupsd Installation Script v0.4.0
set -eo pipefail 2>/dev/null || set -e
echo "=== PVE UPS Manager: apcupsd Installation ==="
echo ""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f /etc/pve/version ]; then
  echo "[WARN] This does not appear to be a Proxmox VE host"
  if [ -t 0 ]; then read -p "Continue? [y/N] " c; if [ "$c" != "y" ] && [ "$c" != "Y" ]; then exit 1; fi
  else echo "[INFO] Non-interactive mode, continuing..."; fi
fi
echo "[INFO] Installing apcupsd..."
apt-get update -qq
apt-get install -y apcupsd

backup_dir="/etc/apcupsd/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
[ -f /etc/apcupsd/apcupsd.conf ] && cp /etc/apcupsd/apcupsd.conf "$backup_dir/"
echo "[OK] Config backed up to $backup_dir"

SHUTDOWN_SCRIPT="$PROJECT_DIR/scripts/pve-ups-shutdown.sh"
if [ -f "$SHUTDOWN_SCRIPT" ]; then
  cp "$SHUTDOWN_SCRIPT" /usr/local/bin/pve-ups-shutdown
  chmod +x /usr/local/bin/pve-ups-shutdown
  echo "[OK] Shutdown script installed"
fi

[ -f /etc/apcupsd/apccontrol ] && [ ! -f /etc/apcupsd/apccontrol.real ] && cp /etc/apcupsd/apccontrol /etc/apcupsd/apccontrol.real
cat > /etc/apcupsd/apccontrol << 'APCEOF'
#!/bin/sh
# PVE UPS Manager - apcupsd control script
case "$1" in
  powerout|battlow|timeout|doshutdown)
    logger "apcupsd: UPS event $1 detected, initiating PVE safe shutdown"
    /usr/local/bin/pve-ups-shutdown
    ;;
esac
if [ -x /etc/apcupsd/apccontrol.real ]; then exec /etc/apcupsd/apccontrol.real "$@"; fi
APCEOF
chmod +x /etc/apcupsd/apccontrol
systemctl enable apcupsd 2>/dev/null || true
echo ""
echo "=== apcupsd Installation Complete ==="
echo "Next steps:"
echo "  1. Edit /etc/apcupsd/apcupsd.conf"
echo "  2. Set BATTERYLEVEL and MINUTES thresholds"
echo "  3. Start: systemctl start apcupsd"
echo "  4. Test: apcaccess"
