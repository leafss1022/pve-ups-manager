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
    // Check for UPS tools. In remote NUT mode (NAS), only nut-client (upsc) is needed locally.
    exec('which upsc upsmon apcaccess apcupsd 2>&1 || dpkg -l 2>/dev/null | grep -i -E "nut|apcupsd" 2>&1 || echo "no tools found"', (err, stdout, stderr) => {
        const hasNUT = stdout.includes('nut') || stdout.includes('upsc') || stdout.includes('upsd');
        const hasAPC = stdout.includes('apcupsd') || stdout.includes('apcaccess');
        res.json({ success: true, hasNUT, hasAPC, output: stdout || stderr });
    });
});

module.exports = router;
