#!/bin/bash
# PVE UPS Manager - Quick install script v0.6.0
# One-click deployment on Proxmox VE host
# Supports local NUT / apcupsd and remote NUT (e.g. NAS-mounted UPS)

set -eo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/leafss1022/pve-ups-manager/main/scripts/quick-install.sh"
REPO_URL="https://github.com/leafss1022/pve-ups-manager.git"
INSTALL_DIR="/opt/pve-ups-manager"

echo "=== PVE UPS Manager 一键部署 (v0.6.0) ==="
echo ""

# ─── Self-reexec: if running from curl pipe, download fresh copy ───
if [[ "$0" == /dev/fd/* ]] || [[ "$0" == "/dev/stdin" ]] || [[ -z "$BASH_SOURCE" ]]; then
    echo "检测到通过 curl 管道运行，正在获取最新脚本..."
    TMP_SCRIPT=$(mktemp /tmp/pve-ups-install.XXXXXX.sh)
    if curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null; then
        chmod +x "$TMP_SCRIPT"
        exec bash "$TMP_SCRIPT"
    else
        echo "[警告] 无法下载最新脚本，继续使用当前版本..."
    fi
fi

# ─── Helper ───
has_cmd() { command -v "$1" &>/dev/null; }

# ─── Node.js installation ───
install_nodejs() {
    echo "正在安装 Node.js 20.x ..."
    echo ""

    # Method 1: NodeSource apt repository
    if has_cmd apt-get; then
        echo "  [1/3] 尝试通过 NodeSource apt 源安装..."
        apt-get update -qq 2>/dev/null || true
        apt-get install -y ca-certificates curl gnupg 2>/dev/null || true
        mkdir -p /etc/apt/keyrings 2>/dev/null
        if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null; then
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
            apt-get update -qq 2>/dev/null || true
            if apt-get install -y nodejs 2>/dev/null; then
                if has_cmd node && has_cmd npm; then
                    echo "  ✓ NodeSource 安装成功"
                    return 0
                fi
            fi
        fi
        echo "  ✗ NodeSource 方式失败"
        echo ""
    fi

    # Method 2: Direct binary download
    echo "  [2/3] 尝试直接下载 Node.js 二进制包..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) NODE_ARCH="linux-x64" ;;
        aarch64|arm64) NODE_ARCH="linux-arm64" ;;
        *) echo "  ✗ 不支持的架构: $ARCH"; echo ""; return 1 ;;
    esac

    NODE_VERSION="v20.18.0"
    NODE_TAR="node-${NODE_VERSION}-${NODE_ARCH}.tar.xz"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TAR}"
    TMP_DIR=$(mktemp -d)

    if curl -fsSL "$NODE_URL" -o "$TMP_DIR/$NODE_TAR" 2>/dev/null; then
        tar -xf "$TMP_DIR/$NODE_TAR" -C /usr/local --strip-components=1 2>/dev/null
        rm -rf "$TMP_DIR"
        if has_cmd node && has_cmd npm; then
            echo "  ✓ 二进制包安装成功"
            return 0
        fi
    fi
    rm -rf "$TMP_DIR"
    echo "  ✗ 二进制包下载失败"
    echo ""

    # Method 3: nvm
    echo "  [3/3] 尝试通过 nvm 安装..."
    if ! has_cmd nvm; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.6.0/install.sh 2>/dev/null | bash 2>/dev/null || true
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    fi
    if has_cmd nvm 2>/dev/null || [ -s "$HOME/.nvm/nvm.sh" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        if nvm install 20 2>/dev/null && nvm use 20 2>/dev/null; then
            if has_cmd node && has_cmd npm; then
                echo "  ✓ nvm 安装成功"
                NODE_PATH=$(which node 2>/dev/null)
                if [ -n "$NODE_PATH" ] && [ ! -f /usr/local/bin/node ]; then
                    ln -sf "$NODE_PATH" /usr/local/bin/node
                    NPM_PATH=$(which npm 2>/dev/null)
                    [ -n "$NPM_PATH" ] && ln -sf "$NPM_PATH" /usr/local/bin/npm
                    npx_path=$(which npx 2>/dev/null)
                    [ -n "$npx_path" ] && ln -sf "$npx_path" /usr/local/bin/npx
                fi
                return 0
            fi
        fi
    fi
    echo "  ✗ nvm 安装失败"
    echo ""
    return 1
}

# ─── Install UPS client tools (nut-client only for remote UPS mode) ───
install_ups_tools() {
    echo "正在自动安装 UPS 客户端工具 (nut-client)..."
    if has_cmd apt-get; then
        apt-get install -y nut-client nut 2>/dev/null || apt-get install -y nut-client 2>/dev/null || true
    fi
    mkdir -p /etc/pve-ups-manager
    if [ ! -f /etc/pve-ups-manager/settings.json ]; then
        cat > /etc/pve-ups-manager/settings.json << 'SETTINGSEOF'
{
  "nutHost": "",
  "nutUps": "ups"
}
SETTINGSEOF
    fi
    echo "  nut-client 已自动安装"
    echo "  可通过 Web 设置页面配置 NUT 服务器地址和 UPS 名称"
}


# ══════════════════ Main Install ══════════════════

# ─── Check / install Node.js ───
HAVE_NODE=false
if has_cmd node; then
    NODE_MAJOR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
        HAVE_NODE=true
        echo "检测到已安装 Node.js $(node -v)"
    else
        echo "检测到 Node.js $(node -v) 版本过低 (需要 18+)，将安装新版本..."
    fi
fi

if [ "$HAVE_NODE" = false ]; then
    install_nodejs || {
        echo ""
        echo "=========================================="
        echo "[错误] Node.js 安装失败"
        echo "=========================================="
        echo "请手动安装 Node.js 18+ 后重新运行此脚本"
        echo ""
        echo "  方式1 (Debian/Ubuntu/PVE):"
        echo "    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
        echo "    apt-get install -y nodejs"
        echo ""
        echo "  方式2 (手动下载):"
        echo "    访问 https://nodejs.org/en/download/ 下载对应平台安装包"
        echo ""
        echo "安装完成后重新运行："
        echo "  bash <(curl -sL ${SCRIPT_URL})"
        echo ""
        exit 1
    }
fi

if ! has_cmd node || ! has_cmd npm; then
    echo "[错误] Node.js 或 npm 不可用，请检查 PATH"
    exit 1
fi

echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"
echo ""

# ─── Download / update project ───
echo "正在下载项目..."
cd /opt
if [ -d pve-ups-manager ]; then
    cd pve-ups-manager
    git fetch --all 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || git pull --ff-only 2>/dev/null || true
else
    git clone "$REPO_URL"
    cd pve-ups-manager
fi
echo "  ✓ 项目代码已更新"
echo ""

# ─── Install backend dependencies ───
echo "正在安装后端依赖..."
cd backend
rm -rf node_modules 2>/dev/null || true
npm install --production 2>&1 | tail -5
if [ ! -d node_modules ]; then
    echo "[错误] 依赖安装失败"
    exit 1
fi
echo "  ✓ 依赖安装完成"
echo ""

# ─── Install UPS tools ───
install_ups_tools

# ─── Get node binary path for systemd ───
NODE_BIN=$(which node)

# ─── Create systemd service ───
echo "创建系统服务..."
cat > /etc/systemd/system/pve-ups-manager.service << EOF
[Unit]
Description=PVE UPS Manager
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/backend
ExecStart=${NODE_BIN} ${INSTALL_DIR}/backend/app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/.nvm/versions/node/$(node -v)/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-ups-manager 2>/dev/null || true
systemctl restart pve-ups-manager

# ─── Wait and check service health ───
echo "等待服务启动..."
sleep 3

MAX_RETRIES=5
RETRY=0
SERVICE_OK=false

while [ $RETRY -lt $MAX_RETRIES ]; do
    if systemctl is-active --quiet pve-ups-manager; then
        if curl -sf --max-time 3 "http://localhost:3456/api/system/info" >/dev/null 2>&1; then
            SERVICE_OK=true
            break
        fi
    fi
    RETRY=$((RETRY + 1))
    echo "  等待中... ($RETRY/$MAX_RETRIES)"
    sleep 2
done

echo ""
if [ "$SERVICE_OK" = true ]; then
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$HOST_IP" ]; then
        HOST_IP="<你的服务器IP>"
    fi
    echo "=== 部署成功！==="
    echo ""
    echo "  访问地址: http://$HOST_IP:3456"
    echo "  管理命令: systemctl status pve-ups-manager"
    echo "  日志查看: journalctl -u pve-ups-manager -f"
    echo ""
    echo "  卸载: bash /opt/pve-ups-manager/scripts/uninstall.sh"
    echo ""
    echo "  如需安装 NUT:     bash /opt/pve-ups-manager/scripts/install-nut.sh"
    echo "  如需安装 apcupsd: bash /opt/pve-ups-manager/scripts/install-apcupsd.sh"
    echo ""
    echo "  配置远程 NUT 地址: 编辑 /etc/pve-ups-manager/settings.json"
    echo ""
    echo "  版本: v0.6.0"
else
    echo "=== 部署完成，但服务可能未正常运行 ==="
    echo ""
    echo "  请检查日志排查问题:"
    echo "    journalctl -u pve-ups-manager -n 30 --no-pager"
    echo ""
    echo "  手动启动测试:"
    echo "    cd /opt/pve-ups-manager/backend && node app.js"
    echo ""
    echo "  常见问题:"
    echo "    - 端口 3456 被占用: ss -tlnp | grep 3456"
    echo "    - 权限问题: 确保以 root 运行"
fi
echo ""
