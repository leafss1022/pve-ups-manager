set if [[ "$0" == /dev/fd/* ]] || [[ "$0" == "/dev/stdin" ]] || [[ -z "$BASH_SOURCE" ]]; then
    echo "检测到通过 curl 管道运行，正在获取最新脚本..."
    if command -v mktemp &>/dev/null; then
        TMP_SCRIPT=$(mktemp /tmp/pve-ups-install.XXXXXX.sh 2>/dev/null)
    else
        TMP_SCRIPT="/tmp/pve-ups-install-$.sh"
    fi
    if [ -n "$TMP_SCRIPT" ] && curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null; then
        chmod +x "$TMP_SCRIPT"
        exec bash "$TMP_SCRIPT"
    else
        echo "警告: 无法下载最新脚本，继续使用当前版本..."
    fi
fi
set -e

if [[ "$0" == /dev/fd/* ]] || [[ "$0" == "/dev/stdin" ]] || [[ -z "$BASH_SOURCE" ]]; then
    echo "????? curl ?????????????..."
    if command -v mktemp &>/dev/null; then
        TMP_SCRIPT=$(mktemp /tmp/pve-ups-install.XXXXXX.sh 2>/dev/null)
    else
        TMP_SCRIPT="/tmp/pve-ups-install-$$.sh"
    fi
    if [ -n "$TMP_SCRIPT" ] && curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null; then
        chmod +x "$TMP_SCRIPT"
        exec bash "$TMP_SCRIPT"
    else
        echo "[??] ?????????????????..."
    fi
fi
set -e



# 鈹€鈹€鈹€ Helper: check if a command exists 鈹€鈹€鈹€
has_cmd() { command -v "$1" &>/dev/null; }

# 鈹€鈹€鈹€ Node.js installation 鈹€鈹€鈹€
install_nodejs() {
    echo "姝ｅ湪瀹夎 Node.js 20.x ..."
    echo ""

    # Method 1: NodeSource apt repository (Debian/Ubuntu/PVE)
    if has_cmd apt-get; then
        echo "  [1/3] 灏濊瘯閫氳繃 NodeSource apt 婧愬畨瑁?.."
        apt-get update -qq 2>/dev/null || true
        apt-get install -y ca-certificates curl gnupg 2>/dev/null || true
        mkdir -p /etc/apt/keyrings 2>/dev/null
        if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null; then
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
            apt-get update -qq 2>/dev/null || true
            if apt-get install -y nodejs 2>/dev/null; then
                if has_cmd node && has_cmd npm; then
                    echo "  鉁?NodeSource 瀹夎鎴愬姛"
                    return 0
                fi
            fi
        fi
        echo "  鉁?NodeSource 鏂瑰紡澶辫触"
        echo ""
    fi

    # Method 2: Direct binary download from nodejs.org
    echo "  [2/3] 灏濊瘯鐩存帴涓嬭浇 Node.js 浜岃繘鍒跺寘..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) NODE_ARCH="linux-x64" ;;
        aarch64|arm64) NODE_ARCH="linux-arm64" ;;
        *) echo "  鉁?涓嶆敮鎸佺殑鏋舵瀯: $ARCH"; echo ""; return 1 ;;
    esac

    NODE_VERSION="v20.18.0"
    NODE_TAR="node-${NODE_VERSION}-${NODE_ARCH}.tar.xz"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TAR}"
    TMP_DIR=$(mktemp -d)

    if curl -fsSL "$NODE_URL" -o "$TMP_DIR/$NODE_TAR" 2>/dev/null; then
        tar -xf "$TMP_DIR/$NODE_TAR" -C /usr/local --strip-components=1 2>/dev/null
        rm -rf "$TMP_DIR"
        if has_cmd node && has_cmd npm; then
            echo "  鉁?浜岃繘鍒跺寘瀹夎鎴愬姛 (瀹夎鍒?/usr/local)"
            return 0
        fi
    fi
    rm -rf "$TMP_DIR"
    echo "  鉁?浜岃繘鍒跺寘涓嬭浇澶辫触"
    echo ""

    # Method 3: Try nvm
    echo "  [3/3] 灏濊瘯閫氳繃 nvm 瀹夎..."
    if ! has_cmd nvm; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.3.0/install.sh 2>/dev/null | bash 2>/dev/null || true
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    fi
    if has_cmd nvm 2>/dev/null || [ -s "$HOME/.nvm/nvm.sh" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        if nvm install 20 2>/dev/null && nvm use 20 2>/dev/null; then
            if has_cmd node && has_cmd npm; then
                echo "  鉁?nvm 瀹夎鎴愬姛"
                # Create symlinks so systemd can find node
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
    echo "  鉁?nvm 瀹夎澶辫触"
    echo ""
    return 1
}

# 鈹€鈹€鈹€ Check existing Node.js 鈹€鈹€鈹€
HAVE_NODE=false
if has_cmd node; then
    NODE_MAJOR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
        HAVE_NODE=true
        echo "妫€娴嬪埌宸插畨瑁?Node.js $(node -v)"
    else
        echo "妫€娴嬪埌 Node.js $(node -v) 鐗堟湰杩囦綆 (闇€瑕?18+)锛屽皢瀹夎鏂扮増鏈?.."
    fi
fi

if [ "$HAVE_NODE" = false ]; then
    install_nodejs || {
        echo ""
        echo "=========================================="
        echo "[閿欒] Node.js 瀹夎澶辫触锛?
        echo "=========================================="
        echo "璇锋墜鍔ㄥ畨瑁?Node.js 18+ 鍚庨噸鏂拌繍琛屾鑴氭湰锛?
        echo ""
        echo "  鏂瑰紡1 (Debian/Ubuntu/PVE):"
        echo "    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
        echo "    apt-get install -y nodejs"
        echo ""
        echo "  鏂瑰紡2 (鎵嬪姩涓嬭浇):"
        echo "    璁块棶 https://nodejs.org/en/download/ 涓嬭浇瀵瑰簲骞冲彴瀹夎鍖?
        echo ""
        echo "瀹夎瀹屾垚鍚庨噸鏂拌繍琛岋細"
        echo "  bash <(curl -sL ${SCRIPT_URL})"
        echo ""
        exit 1
    }
fi

# 鈹€鈹€鈹€ Verify node and npm are available 鈹€鈹€鈹€
if ! has_cmd node; then
    echo "[閿欒] Node.js 瀹夎鍚庝粛鏃犳硶鎵惧埌 node 鍛戒护"
    echo "璇锋鏌?PATH 鐜鍙橀噺鎴栨墜鍔ㄥ畨瑁?
    exit 1
fi
if ! has_cmd npm; then
    echo "[閿欒] npm 鏈畨瑁呫€傚皾璇曞崟鐙畨瑁?npm..."
    if has_cmd apt-get; then
        apt-get install -y npm 2>/dev/null || true
    fi
    if ! has_cmd npm; then
        echo "[閿欒] npm 瀹夎澶辫触锛岃鎵嬪姩瀹夎"
        exit 1
    fi
fi

echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"
echo ""

# 鈹€鈹€鈹€ Download / update project 鈹€鈹€鈹€
echo "姝ｅ湪涓嬭浇椤圭洰..."
cd /opt
if [ -d pve-ups-manager ]; then
    cd pve-ups-manager
    git fetch --all 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || git pull --ff-only 2>/dev/null || true
else
    git clone "$REPO_URL"
    cd pve-ups-manager
fi
echo "  鉁?椤圭洰浠ｇ爜宸叉洿鏂?
echo ""

# 鈹€鈹€鈹€ Install backend dependencies 鈹€鈹€鈹€
echo "姝ｅ湪瀹夎鍚庣渚濊禆..."
cd backend
# Clean install to avoid stale lock file issues
rm -rf node_modules 2>/dev/null || true
npm install --production 2>&1 | tail -5
if [ ! -d node_modules ]; then
    echo "[閿欒] 渚濊禆瀹夎澶辫触"
    exit 1
fi
echo "  鉁?渚濊禆瀹夎瀹屾垚"
echo ""

# 鈹€鈹€鈹€ Get node binary path for systemd service 鈹€鈹€鈹€
NODE_BIN=$(which node)

# 鈹€鈹€鈹€ Create systemd service 鈹€鈹€鈹€
echo "鍒涘缓绯荤粺鏈嶅姟..."
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

# Ensure node is in PATH (for nvm installs)
Environment=PATH=/usr/local/bin:/usr/bin:/bin:${HOME}/.nvm/versions/node/$(node -v)/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-ups-manager 2>/dev/null || true
systemctl restart pve-ups-manager

# 鈹€鈹€鈹€ Wait and check service health 鈹€鈹€鈹€
echo "绛夊緟鏈嶅姟鍚姩..."
sleep 3

MAX_RETRIES=5
RETRY=0
SERVICE_OK=false

while [ $RETRY -lt $MAX_RETRIES ]; do
    if systemctl is-active --quiet pve-ups-manager; then
        # Check if the HTTP port is responding
        if curl -sf --max-time 3 "http://localhost:13456/api/system/info" >/dev/null 2>&1; then
            SERVICE_OK=true
            break
        fi
    fi
    RETRY=$((RETRY + 1))
    echo "  绛夊緟涓?.. ($RETRY/$MAX_RETRIES)"
    sleep 2
done

echo ""
if [ "$SERVICE_OK" = true ]; then
    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$HOST_IP" ]; then
        HOST_IP="<浣犵殑鏈嶅姟鍣↖P>"
    fi
    echo "=== 閮ㄧ讲鎴愬姛锛?==="
    echo ""
    echo "  璁块棶鍦板潃: http://$HOST_IP:13456"
    echo "  绠＄悊鍛戒护: systemctl status pve-ups-manager"
    echo "  鏃ュ織鏌ョ湅: journalctl -u pve-ups-manager -f"
    echo ""
    echo "  濡傞渶瀹夎 NUT:     bash /opt/pve-ups-manager/scripts/install-nut.sh"
    echo "  濡傞渶瀹夎 apcupsd: bash /opt/pve-ups-manager/scripts/install-apcupsd.sh"
    echo ""
    echo "  鐗堟湰: v0.3.0"
else
    echo "=== 閮ㄧ讲瀹屾垚锛屼絾鏈嶅姟鍙兘鏈甯歌繍琛?==="
    echo ""
    echo "  璇锋鏌ユ棩蹇楁帓鏌ラ棶棰?"
    echo "    journalctl -u pve-ups-manager -n 30 --no-pager"
    echo ""
    echo "  鎵嬪姩鍚姩娴嬭瘯:"
    echo "    cd /opt/pve-ups-manager/backend && node app.js"
    echo ""
    echo "  甯歌闂:"
    echo "    - 绔彛 13456 琚崰鐢? ss -tlnp | grep 13456"
    echo "    - 鏉冮檺闂: 纭繚浠?root 杩愯"
fi
echo ""
