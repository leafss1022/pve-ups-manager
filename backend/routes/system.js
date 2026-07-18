const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const os = require('os');

// ============ GET: System Information ============
router.get('/info', (req, res) => {
    exec('uname -a 2>&1 && echo "---" && cat /etc/os-release 2>&1 && echo "---" && free -h 2>&1 && echo "---" && df -h / 2>&1', (err, stdout, stderr) => {
        const info = {
            hostname: os.hostname(),
            platform: os.platform(),
            arch: os.arch(),
            cpus: os.cpus().length,
            totalMem: os.totalmem(),
            freeMem: os.freemem(),
            uptime: os.uptime(),
            network: os.networkInterfaces()
        };
        res.json({ success: true, system: info, raw: stdout || stderr });
    });
});

// ============ GET: Installed UPS Tools ============
router.get('/tools', (req, res) => {
    exec('which nut-server upsd upsc upsmon apcupsd apcaccess 2>&1 || dpkg -l | grep -E "nut|apcupsd" 2>&1 || echo "nut not found"', (err, stdout, stderr) => {
        const hasNUT = stdout.includes('nut') || stdout.includes('upsd') || stdout.includes('upsc');
        const hasAPC = stdout.includes('apcupsd') || stdout.includes('apcaccess');
        res.json({ success: true, hasNUT, hasAPC, output: stdout || stderr });
    });
});

module.exports = router;
