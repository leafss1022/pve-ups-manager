#!/bin/bash
# PVE UPS Manager - NUT Installation Script v0.4.0
set -eo pipefail 2>/dev/null || set -e
echo "=== PVE UPS Manager: NUT Installation ==="
echo ""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f /etc/pve/version ]; then
  echo "[WARN] This does not appear to be a Proxmox VE host"
  if [ -t 0 ]; then read -p "Continue? [y/N] " c; if [ "$c" != "y" ] && [ "$c" != "Y" ]; then exit 1; fi
  else echo "[INFO] Non-interactive mode, continuing..."; fi
fi
echo "[INFO] Installing NUT packages..."
apt-get update -qq
apt-get install -y nut nut-client nut-server

backup_dir="/etc/nut/backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"
for f in ups.conf upsd.conf upsd.users upsmon.conf; do [ -f "/etc/nut/$f" ] && cp "/etc/nut/$f" "$backup_dir/"; done
echo "[OK] Config backed up to $backup_dir"

SHUTDOWN_SCRIPT="$PROJECT_DIR/scripts/pve-ups-shutdown.sh"
if [ -f "$SHUTDOWN_SCRIPT" ]; then
  cp "$SHUTDOWN_SCRIPT" /usr/local/bin/pve-ups-shutdown
  chmod +x /usr/local/bin/pve-ups-shutdown
  echo "[OK] Shutdown script installed"
fi

if [ -f /etc/nut/upsmon.conf ]; then
  if grep -q "^SHUTDOWNCMD" /etc/nut/upsmon.conf 2>/dev/null; then
    sed -i 's|^SHUTDOWNCMD.*|SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"|' /etc/nut/upsmon.conf
  else
    echo 'SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"' >> /etc/nut/upsmon.conf
  fi
else
  echo 'SHUTDOWNCMD "/usr/local/bin/pve-ups-shutdown"' > /etc/nut/upsmon.conf
fi

systemctl enable nut-server nut-monitor 2>/dev/null || true
systemctl restart nut-server nut-monitor 2>/dev/null || true
echo ""
echo "=== NUT Installation Complete ==="
echo "Next steps:"
echo "  1. Edit /etc/nut/ups.conf"
echo "  2. Edit /etc/nut/upsd.conf"
echo "  3. Edit /etc/nut/upsd.users"
echo "  4. Edit /etc/nut/upsmon.conf"
echo "  5. Restart: systemctl restart nut-server nut-monitor"
echo "  6. Test: upsc ups@localhost"
