const fs = require("fs");
const b = "C:\\Users\\44853\\Documents\\pve-ups";

// 2. Fix system.js - tool detection: remote NUT scenario (no local NUT server)
let sys = fs.readFileSync(b + "\\backend\\routes\\system.js", "utf8");
const oldTools = `    exec('which nut-server upsd upsc upsmon apcupsd apcaccess 2>&1 || dpkg -l | grep -E "nut|apcupsd" 2>&1 || echo "nut not found"', (err, stdout, stderr) => {`;
const newTools = `    // Check for UPS tools. In remote NUT mode (NAS), only nut-client (upsc) is needed locally.
    exec('which upsc upsmon apcaccess apcupsd 2>&1 || dpkg -l 2>/dev/null | grep -i -E "nut|apcupsd" 2>&1 || echo "no tools found"', (err, stdout, stderr) => {`;
sys = sys.replace(oldTools, newTools);
const oldHas = `        const hasNUT = stdout.includes('nut') || stdout.includes('upsd') || stdout.includes('upsc');`;
const newHas = `        const hasNUT = stdout.includes('nut') || stdout.includes('upsc') || stdout.includes('upsd');`;
sys = sys.replace(oldHas, newHas);
fs.writeFileSync(b + "\\backend\\routes\\system.js", sys, "utf8");
console.log("system.js: remote NUT detection fixed");