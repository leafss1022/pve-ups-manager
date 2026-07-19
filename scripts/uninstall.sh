#!/bin/bash
# PVE UPS Manager - Uninstall Script v0.6.0
# One-click removal of PVE UPS Manager and optional UPS tools

set -eo pipefail

INSTALL_DIR="/opt/pve-ups-manager"

echo "=== PVE UPS Manager 卸载 (v0.6.0) ==="
echo ""

# Confirm
read -p "确定要卸载 PVE UPS Manager? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "取消卸载"
    exit 0
fi

# ─── Stop and remove systemd service ───
echo "停止并移除系统服务..."
if systemctl is-active --quiet pve-ups-manager 2>/dev/null; then
    systemctl stop pve-ups-manager
fi
systemctl disable pve-ups-manager 2>/dev/null || true
rm -f /etc/systemd/system/pve-ups-manager.service
systemctl daemon-reload
echo "  ✓ 系统服务已移除"

# ─── Remove install directory ───
if [ -d "$INSTALL_DIR" ]; then
    echo "删除安装目录 $INSTALL_DIR ..."
    rm -rf "$INSTALL_DIR"
    echo "  ✓ 安装目录已删除"
fi

# ─── Remove settings ───
if [ -d /etc/pve-ups-manager ]; then
    read -p "是否删除 NUT 连接配置 (/etc/pve-ups-manager)? [y/N] " del_cfg
    if [ "$del_cfg" = "y" ] || [ "$del_cfg" = "Y" ]; then
        rm -rf /etc/pve-ups-manager
        echo "  ✓ 配置已删除"
    fi
fi

# ─── Remove shutdown hook ───
if [ -f /usr/local/bin/pve-ups-shutdown ]; then
    rm -f /usr/local/bin/pve-ups-shutdown
    echo "  ✓ 关机脚本已移除"
fi

# ─── Ask about UPS tools ───
echo ""
echo "是否同时卸载 UPS 工具?"
echo "  1) 卸载 nut-client (远程 NUT 模式)"
echo "  2) 卸载完整 NUT (nut-server + nut-client)"
echo "  3) 卸载 apcupsd"
echo "  4) 保留 UPS 工具不变 (默认)"
echo ""
read -p "请输入选项 [1-4] (默认 4): " tool_choice
tool_choice="${tool_choice:-4}"

case "$tool_choice" in
    1)
        echo "卸载 nut-client..."
        if has_cmd apt-get; then
            apt-get remove -y nut-client 2>/dev/null || true
        fi
        echo "  ✓ nut-client 已卸载"
        ;;
    2)
        echo "卸载完整 NUT..."
        if has_cmd apt-get; then
            apt-get remove -y nut nut-server nut-client 2>/dev/null || true
        fi
        echo "  ✓ NUT 已卸载"
        ;;
    3)
        echo "卸载 apcupsd..."
        if has_cmd apt-get; then
            apt-get remove -y apcupsd 2>/dev/null || true
        fi
        if [ -f /etc/apcupsd/apccontrol.real ]; then
            mv /etc/apcupsd/apccontrol.real /etc/apcupsd/apccontrol
        fi
        echo "  ✓ apcupsd 已卸载"
        ;;
    *)
        echo "跳过 UPS 工具卸载"
        ;;
esac

echo ""
echo "=== 卸载完成 ==="
echo "PVE UPS Manager 已从系统中移除。"
echo "如有残留配置，请手动清理:"
echo "  /etc/nut/    (NUT 配置，如不再需要可删除)"
echo "  /etc/apcupsd/ (apcupsd 配置，如不再需要可删除)"
