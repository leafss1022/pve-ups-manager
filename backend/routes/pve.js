const express = require("express");
const router = express.Router();
const { exec } = require("child_process");

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

function parseQmList(output) {
    const lines = output.split("\n").filter(l => l.trim());
    if (lines.length < 2) return [];
    const result = [];
    for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].trim().split(/\s+/);
        if (parts.length >= 4) {
            result.push({ vmid: parts[0], name: parts[1], status: parts[2], memory: parts[3] });
        }
    }
    return result;
}

function parsePctList(output) {
    const lines = output.split("\n").filter(l => l.trim());
    if (lines.length < 2) return [];
    const result = [];
    for (let i = 1; i < lines.length; i++) {
        const parts = lines[i].trim().split(/\s+/);
        if (parts.length >= 4) {
            result.push({ vmid: parts[0], name: parts[1], status: parts[2], memory: parts.length > 3 ? parts[3] : "N/A" });
        }
    }
    return result;
}

router.post("/shutdown", (req, res) => {
    const { mode, delay } = req.body;
    const shutdownDelay = delay || 60;
    const cmds = [];
    if (mode === "vms_only" || mode === "all") {
        cmds.push("for vmid in $(qm list | awk '{if(NR>1) print \$1}'); do qm shutdown $vmid --timeout 30; done");
        cmds.push("for vmid in $(pct list | awk '{if(NR>1) print \$1}'); do pct shutdown $vmid --timeout 30; done");
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

module.exports = router;
