const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const fs2 = require('fs');

const APCUPSD_CONF = '/etc/apcupsd/apcupsd.conf';

// ============ GET: Read apcupsd Config ============
router.get('/config', (req, res) => {
    try {
        if (fs2.existsSync(APCUPSD_CONF)) {
            const content = fs2.readFileSync(APCUPSD_CONF, 'utf8');
            return res.json({ success: true, config: content });
        }
        res.json({ success: false, message: 'apcupsd config not found' });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

// ============ POST: Save apcupsd Config ============
router.post('/config', (req, res) => {
    const { content } = req.body;
    if (content === undefined) {
        return res.status(400).json({ success: false, message: 'Missing content' });
    }
    try {
        fs2.writeFileSync(APCUPSD_CONF, content, 'utf8');
        res.json({ success: true, message: 'apcupsd.conf saved' });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
});

// ============ GET: UPS Status via apcaccess ============
router.get('/status', (req, res) => {
    exec('apcaccess 2>&1', (err, stdout, stderr) => {
        if (err) {
            return res.json({ success: false, status: 'disconnected', message: 'apcupsd not running: ' + (stderr || err.message) });
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

// ============ POST: Restart apcupsd ============
router.post('/restart', (req, res) => {
    exec('systemctl restart apcupsd 2>&1 || service apcupsd restart 2>&1', (err, stdout, stderr) => {
        res.json({
            success: !err,
            message: err ? 'Restart failed: ' + (stderr || err.message) : 'apcupsd restarted',
            output: stdout || stderr
        });
    });
});

module.exports = router;
