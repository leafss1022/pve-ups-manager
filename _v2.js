const fs = require("fs");
const p = "C:\\Users\\44853\\Documents\\pve-ups";

// Update README.md - add 远程NAS场景说明
let readme = fs.readFileSync(p + "\\README.md", "utf8");

// Update version
readme = readme.replace(/v0\.\d+\.\d+/g, "v0.6.0");

// Add remote NUT section
const remoteSection = `\n## 远程 NUT (NAS 场景)\n\n当 UPS 连接在 NAS 或其他服务器上，PVE 通过远程 NUT 协议获取状态：\n\n1. NAS 端安装 NUT (nut-server)，UPS 通过 USB/串口连接\n2. PVE 端仅安装 nut-client (无需 nut-server)\n3. 在 PVE UPS Manager 的"设置"页面配置 NUT 服务器地址 (如 192.168.10.7)\n4. WebSocket 自动推送到前端，无需定时轮询\n\n需确保 PVE 能访问 NAS 的 3493 端口 (NUT 默认端口)。\n`;

if (!readme.includes("远程 NUT")) {
    readme = readme.replace("## 快速开始", remoteSection + "\n## 快速开始");
}

fs.writeFileSync(p + "\\README.md", readme, "utf8");
console.log("README.md: updated with remote NUT docs");

// Update php-monitor/ups.php version
let php = fs.readFileSync(p + "\\php-monitor\\ups.php", "utf8");
php = php.replace(/v0\.\d+\.\d+/g, "v0.6.0");
fs.writeFileSync(p + "\\php-monitor\\ups.php", php, "utf8");
console.log("ups.php: v0.6.0");

// Update scripts versions
const scripts = ["quick-install.sh", "install-nut.sh", "install-apcupsd.sh", "install-php-monitor.sh", "uninstall.sh", "pve-ups-shutdown.sh"];
scripts.forEach(s => {
    try {
        let c = fs.readFileSync(p + "\\scripts\\" + s, "utf8");
        c = c.replace(/v0\.\d+\.\d+/g, "v0.6.0");
        fs.writeFileSync(p + "\\scripts\\" + s, c, "utf8");
        console.log(s + ": v0.6.0");
    } catch(e) {
        console.log(s + ": " + e.message);
    }
});

console.log("ALL DONE");