#!/bin/bash
# PVE UPS Manager - Uninstall Script v0.4.0
set -eo pipefail 2>/dev/null || set -e
echo "=== PVE UPS Manager Uninstaller (v0.4.0) ==="
echo ""
INSTALL_DIR="/opt/pve-ups-manager"

if [ -t 0 ]; then
  echo "[WARN] This will remove PVE UPS Manager completely."
  read -p "Continue? [y/N] " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then echo "Aborted."; exit 0; fi
  read -p "Remove NUT/apcupsd configs too? [y/N] " remove_ups
  read -p "Remove Node.js as well? [y/N] " remove_node
  read -p "Keep logs? [Y/n] " keep_logs
else
  remove_ups="n"; remove_node="n"; keep_logs="y"
fi

echo "[INFO] Stopping service..."
systemctl stop pve-ups-manager 2>/dev/null || true
systemctl disable pve-ups-manager 2>/dev/null || true
echo "[INFO] Removing systemd service..."
rm -f /etc/systemd/system/pve-ups-manager.service
systemctl daemon-reload
echo "[INFO] Removing project files..."
rm -rf "$INSTALL_DIR"
echo "[INFO] Removing shutdown script..."
rm -f /usr/local/bin/pve-ups-shutdown

if [ "$remove_ups" = "y" ] || [ "$remove_ups" = "Y" ]; then
  echo "[INFO] Removing UPS tools..."
  apt-get remove -y nut nut-client nut-server apcupsd 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
  rm -rf /etc/nut /etc/apcupsd
  echo "[OK] UPS tools removed"
fi
if [ "$remove_node" = "y" ] || [ "$remove_node" = "Y" ]; then
  echo "[INFO] Removing Node.js..."
  apt-get remove -y nodejs npm 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true
  rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
  rm -rf /usr/local/lib/node_modules
  echo "[OK] Node.js removed"
fi
if [ "$keep_logs" = "n" ] || [ "$keep_logs" = "N" ]; then
  rm -rf /var/log/pve-ups*
  echo "[OK] Logs removed"
fi
echo ""
echo "=== Uninstall Complete ==="
