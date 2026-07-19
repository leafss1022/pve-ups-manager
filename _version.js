const fs = require("fs");
const b = "C:\\Users\\44853\\Documents\\pve-ups";

// Update package.json
let pkg = JSON.parse(fs.readFileSync(b + "\\package.json", "utf8"));
pkg.version = "0.6.0";
fs.writeFileSync(b + "\\package.json", JSON.stringify(pkg, null, 2) + "\n", "utf8");
console.log("Root package.json: 0.6.0");

// Update backend/package.json
pkg = JSON.parse(fs.readFileSync(b + "\\backend\\package.json", "utf8"));
pkg.version = "0.6.0";
fs.writeFileSync(b + "\\backend\\package.json", JSON.stringify(pkg, null, 2) + "\n", "utf8");
console.log("Backend package.json: 0.6.0");

// Update frontend/package.json
pkg = JSON.parse(fs.readFileSync(b + "\\frontend\\package.json", "utf8"));
pkg.version = "0.6.0";
fs.writeFileSync(b + "\\frontend\\package.json", JSON.stringify(pkg, null, 2) + "\n", "utf8");
console.log("Frontend package.json: 0.6.0");

// Update index.html version badge
let html = fs.readFileSync(b + "\\frontend\\public\\index.html", "utf8");
html = html.replace(/v0\.\d+\.\d+/g, "v0.6.0");
fs.writeFileSync(b + "\\frontend\\public\\index.html", html, "utf8");
console.log("index.html version: 0.6.0");

// Update README.md
let readme = fs.readFileSync(b + "\\README.md", "utf8");
readme = readme.replace(/v0\.\d+\.\d+/g, "v0.6.0");
fs.writeFileSync(b + "\\README.md", readme, "utf8");
console.log("README.md version: 0.6.0");

// Update php-monitor/ups.php version
let php = fs.readFileSync(b + "\\php-monitor\\ups.php", "utf8");
php = php.replace(/v0\.\d+\.\d+/g, "v0.6.0");
fs.writeFileSync(b + "\\php-monitor\\ups.php", php, "utf8");
console.log("ups.php version: 0.6.0");

// Update scripts versions
const scripts = ["quick-install.sh", "install-nut.sh", "install-apcupsd.sh", "install-php-monitor.sh", "uninstall.sh", "pve-ups-shutdown.sh"];
scripts.forEach(s => {
    try {
        let content = fs.readFileSync(b + "\\scripts\\" + s, "utf8");
        content = content.replace(/v0\.\d+\.\d+/g, "v0.6.0");
        fs.writeFileSync(b + "\\scripts\\" + s, content, "utf8");
        console.log(s + ": version updated");
    } catch(e) {
        console.log(s + ": skipped (" + e.message + ")");
    }
});

console.log("ALL VERSIONS UPDATED TO v0.6.0");