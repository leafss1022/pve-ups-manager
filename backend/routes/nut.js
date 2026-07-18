const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const fs2 = require('fs');
const path = require('path');

// ============ NUT Configuration Paths ============
const NUT_CONFIG_DIR = '/etc/nut';
const UPS_CONF = path.join(NUT_CONFIG_DIR, 'ups.conf');
const UPSD_CONF = path.join(NUT_CONFIG_DIR, 'upsd.conf');
const UPSD_USERS = path.join(NUT_CONFIG_DIR, 'upsd.users');
const UPSCONF_CONF = path.join(NUT_CONFIG_DIR, 'upsmon.conf');

// ============ GET: Read NUT Config Files ============
router.get('/config', (req, res) => {
    const configs = {};
    const files = [UPS_CONF, UPSD_CONF, UPSD_USERS, UPSCONF_CONF];
    files.forEach(file => {
        try {
            if (fs2.existsSync(file)) {
                configs[path.basename(file)] = fs2.readFileSync(file, 'utf8');
            }
        } catch (e) {
            configs[path.basename(file)] = 'Error reading: ' + e.message;
        }
    });
    res.json({ success: true, configs });
});

// ============ POST: Save NUT Config File ============
router.post('/config', (req, res) => {
    const { filename, content } = req.body;
    if (!filename || content === undefined) {
        return res.status(400).json({ success: false, message: 'Missing filename or content' });
    }
    const safeFiles = ['ups.conf', 'upsd.conf', 'upsd.users', 'upsmon.conf'];
    if (!safeFiles.includes(filename)) {
        return res.status(400).json({ success: false, message: 'Invalid filename' });
    }
    const filePath = path.join(NUT_CONFIG_DIR, filename);
    try {
        fs2.writeFileSync(filePath, content, 'utf8');
        res.json({ success: true, message: filename + ' saved successfully' });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

// ============ POST: Validate NUT Config ============
router.post('/validate', (req, res) => {
    exec('nutconf -c 2>&1 || upscmd -l 2>&1 || echo "Validation done"', (err, stdout, stderr) => {
        res.json({ success: true, output: stdout || stderr || 'Validation completed (no output)' });
    });
});

// ============ GET: UPS Status ============
router.get('/status', (req, res) => {
    exec('upsc ups@localhost 2>&1 || echo "NUT not running or no UPS configured"', (err, stdout, stderr) => {
        if (err && stdout.includes('not running')) {
            return res.json({ success: false, status: 'disconnected', message: stdout.trim(), diagnose: 'NUT not connected. Check: 1) is NUT installed? 2) is ups.conf configured? 3) are services running? 4) is USB UPS plugged in?' });
        }
        const lines = stdout.split('\n').filter(l => l.trim());
        const parsed = {};
        lines.forEach(line => {
            const parts = line.split(':');
            if (parts.length >= 2) {
                parsed[parts[0].trim()] = parts.slice(1).join(':').trim();
            }
        });
        res.json({ success: true, status: 'connected', data: parsed });
    });
});

// ============ POST: Restart NUT Services ============
router.post('/restart', (req, res) => {
    const cmds = ['systemctl restart nut-server', 'systemctl restart nut-monitor', 'systemctl restart nut-client'];
    exec(cmds.join(' && '), (err, stdout, stderr) => {
        if (err) {
            // Try alternative restart
            exec('service nut-server restart && service nut-monitor restart', (err2, stdout2, stderr2) => {
                res.json({
                    success: !err2,
                    message: err2 ? (err2.message || 'Restart failed') : 'Services restarted',
                    output: stdout2 || stderr2
                });
            });
        } else {
            res.json({ success: true, message: 'NUT services restarted', output: stdout || stderr });
        }
    });
});

module.exports = router;
