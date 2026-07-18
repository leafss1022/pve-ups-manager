const express = require("express");
const router = express.Router();
const { exec, execSync } = require("child_process");

router.get("/list", (req, res) => {
    const cmd = "qm list 2>&1 && echo ---CT--- && pct list 2>&1";
    exec(cmd, (err, stdout, stderr) => {
        if (err && !stdout) {
            return res.json({ success: false, message: "This server does not appear to be a PVE host: " + (stderr || err.message) });
        }
        const parts = stdout.split("---CT---");
        const vms = parseQmList(parts[0] || "");
        const cts = parsePctList(parts[1] || "");
        res.json({ success: true, vms, containers: cts });
    });
});

// qm list output format:
//   VMID NAME       STATUS    MEM(MB)  BOOTDISK(GB)  PID
//   100  test-vm    running   2048     32.00         12345
// VMID=0, NAME=1, STATUS=2, MEM=3
function parseQmList(output) {
    const lines = output.split("\n").filter(l => l.trim());
    if (lines.length < 2) return [];
    const result = [];
    for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].trim().split(/\s+/);
        if (parts.length >= 3) {
            result.push({
                vmid: parts[0],
                name: parts[1],
                status: parts[2],
                memory: parts[3] || "N/A"
            });
        }
    }
    return result;
}

// pct list output format:
//   VMID STATUS
//   200  running
// VMID=0, STATUS=1
function parsePctList(output) {
    const lines = output.split("\n").filter(l => l.trim());
    if (lines.length < 2) return [];
    const result = [];
    for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].trim().split(/\s+/);
        if (parts.length >= 2) {
            result.push({
                vmid: parts[0],
                name: parts[0],
                status: parts[1],
                memory: "N/A"
            });
        }
    }
    return result;
}

router.post("/shutdown", (req, res) => {
    const { mode, delay } = req.body;
    const shutdownDelay = delay || 60;
    const cmds = [];
    if (mode === "vms_only" || mode === "all") {
        cmds.push("for vmid in $(qm list | awk '{if(NR>1) print $1}'); do qm shutdown $vmid --timeout 30; done");
        cmds.push("for vmid in $(pct list | awk '{if(NR>1) print $1}'); do pct shutdown $vmid --timeout 30; done");
    }
    if (mode === "all") {
        cmds.push("sleep " + shutdownDelay);
        cmds.push("shutdown -h +1 \"UPS battery low - system shutting down\"");
    }
    exec(cmds.join(" && "), { timeout: 300000 }, (err, stdout, stderr) => {
        res.json({
            success: !err,
            message: err ? "Shutdown sequence completed with errors: " + (stderr || err.message) : "Shutdown sequence initiated",
            output: stdout || stderr
        });
    });
});

router.post("/test-nut-shutdown", (req, res) => {
    exec("upsmon -c fsd 2>&1 || echo 'NUT forced shutdown test'", (err, stdout, stderr) => {
        res.json({ success: true, message: "FSD signal sent to NUT", output: stdout || stderr });
    });
});



// ============ PVE API backup (for Docker or non-PVE hosts) ============
// Attempt to use PVE API if qm/pct commands are not available
router.get("/api-list", function(req, res) {
    var cmd = "which qm 2>/dev/null && qm list 2>&1 || echo qm-not-available";
    cmd += " && echo ---CT--- && ";    cmd += "which pct 2>/dev/null && pct list 2>&1 || echo pct-not-available";
    exec(cmd, function(err, stdout) {
        if (stdout && stdout.includes("not-available")) {
            // Try PVE API directly
            exec('curl -sk --connect-timeout 5 "https://localhost:8006/api2/json/cluster/resources?type=vm" 2>&1 || echo "pve-api-failed"', function(err2, stdout2) {
                if (stdout2 && !stdout2.includes("pve-api-failed") && !stdout2.includes("Failed")) {
                    try {
                        var data = JSON.parse(stdout2);
                        var vms = [];
                        var cts = [];
                        if (data && data.data) {
                            data.data.forEach(function(item) {
                                if (item.type === "qemu") {
                                    vms.push({ vmid: item.vmid, name: item.name || "VM-" + item.vmid, status: item.status, memory: item.mem || "N/A" });
                                } else if (item.type === "lxc") {
                                    cts.push({ vmid: item.vmid, name: item.name || "CT-" + item.vmid, status: item.status, memory: item.mem || "N/A" });
                                }
                            });
                        }
                        return res.json({ success: true, vms: vms, containers: cts, source: "pve-api" });
                    } catch(e) {
                        return res.json({ success: false, message: "PVE commands not available on this host", source: "error" });
                    }
                } else {
                    return res.json({ success: false, message: "PVE commands and API not available. Run on PVE host or configure PVE API token.", source: "unavailable" });
                }
            });
        } else {
            // Normal qm/pct path
            var parts = stdout.split("---CT---");
            var vms = parseQmList(parts[0] || "");
            var cts = parsePctList(parts[1] || "");
            res.json({ success: true, vms: vms, containers: cts, source: "pve-commands" });
        }
    });
});

module.exports = router;
