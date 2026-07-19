#!/bin/bash
# PVE UPS Monitor - PHP 监控页安装脚本 v0.5.0
set -e

echo "=== PVE UPS Monitor PHP 安装 ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WEB_DIR="/var/www/html"
DATA_DIR="/var/lib/ups-monitor"

# 检测 Web 根目录
if [ ! -d "$WEB_DIR" ]; then
    echo "未检测到 $WEB_DIR，正在安装 Apache + PHP..."
    apt-get update -qq
    apt-get install -y -qq apache2 php php-cli libapache2-mod-php
    WEB_DIR="/var/www/html"
fi

# 检查 PHP
if ! command -v php &> /dev/null; then
    echo "正在安装 PHP..."
    apt-get update -qq
    apt-get install -y -qq php php-cli libapache2-mod-php
fi

echo "PHP: $(php -v | head -1)"

# 复制 ups.php
echo "正在安装监控页面..."
cp "$REPO_DIR/php-monitor/ups.php" "$WEB_DIR/ups.php"
chown www-data:www-data "$WEB_DIR/ups.php"
chmod 644 "$WEB_DIR/ups.php"

# 创建数据目录 (Web 根目录外, 安全)
echo "正在创建数据目录..."
mkdir -p "$DATA_DIR"
chown www-data:www-data "$DATA_DIR"
chmod 755 "$DATA_DIR"

# 初始化配置文件
if [ ! -f "$DATA_DIR/config.json" ]; then
    cat > "$DATA_DIR/config.json" << 'CONF'
{
    "refresh": 10,
    "low_battery": 20,
    "shutdown_delay": 120,
    "ups_host": "127.0.0.1",
    "ups_name": "ups0",
    "theme": "dark",
    "pushplus_token": ""
}
CONF
    chown www-data:www-data "$DATA_DIR/config.json"
fi

# 检查 NUT
if ! command -v upsc &> /dev/null; then
    echo ""
    echo "⚠️  NUT (Network UPS Tools) 未安装!"
    echo "   请运行: bash $REPO_DIR/scripts/install-nut.sh"
else
    echo "NUT: $(upsc --version 2>&1 | head -1)"
fi

# 重启 Apache
echo "正在重启 Web 服务..."
systemctl restart apache2 2>/dev/null || systemctl restart httpd 2>/dev/null || true

# 获取 IP
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$HOST_IP" ]; then HOST_IP="localhost"; fi

echo ""
echo "=== 安装完成! ==="
echo "访问地址: http://$HOST_IP/ups.php"
echo "数据目录: $DATA_DIR"
echo ""
echo "如需安装 NUT: bash $REPO_DIR/scripts/install-nut.sh"
echo "如需安装 apcupsd: bash $REPO_DIR/scripts/install-apcupsd.sh"
