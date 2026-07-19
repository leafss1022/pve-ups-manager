const fs = require("fs");
const b = "C:\\Users\\44853\\Documents\\pve-ups";
let x = fs.readFileSync(b + "\\backend\\routes\\pve.js", "utf8");
const pos = x.indexOf("function parsePctList(output)");
const endPos = x.indexOf("\nrouter.post", pos);
const newText = [
  'function parsePctList(output) {',
  '    const lines = output.split("\\n").filter(l => l.trim());',
  '    if (lines.length < 2) return [];',
  '    const result = [];',
  '    for (let i = 1; i < lines.length; i++) {',
  '        const parts = lines[i].trim().split(/\\s+/);',
  '        if (parts.length >= 3) {',
  '            result.push({ vmid: parts[0], name: parts[1], status: parts[2], memory: "N/A" });',
  '        } else if (parts.length >= 2) {',
  '            result.push({ vmid: parts[0], name: parts[0], status: parts[1], memory: "N/A" });',
  '        }',
  '    }',
  '    return result;',
  '}'
].join("\n");
x = x.substring(0, pos) + newText + x.substring(endPos);
fs.writeFileSync(b + "\\backend\\routes\\pve.js", x, "utf8");
console.log("pve.js fixed: parsePctList handles 3-column PVE 8.x output");