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



// POST: Save apcupsd.conf from form fields
router.post("/config-form", (req, res) => {
  const { cable, type, device, polltime, battLevel, minutes } = req.body;
  let conf = "UPSCABLE " + (cable || "usb") + "\n";
  conf += "UPSTYPE " + (type || "usb") + "\n";
  conf += "DEVICE " + (device || "") + "\n";
  conf += "POLLTIME " + (polltime || "10") + "\n";
  conf += "BATTERYLEVEL " + (battLevel || "30") + "\n";
  conf += "MINUTES " + (minutes || "5") + "\n";
  conf += "TIMEOUT 0\nANNOY 300\nANNOYDELAY 60\nNOLOGON disable\nKILLDELAY 10\nNETSERVER on\nNISIP 0.0.0.0\nNISPORT 3551\n";
  try {
    const fs2 = require("fs");
    fs2.writeFileSync("/etc/apcupsd/apcupsd.conf", conf, "utf8");
    res.json({ success: true, message: "apcupsd.conf saved" });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// GET: Parse apcupsd.conf to form fields
router.get("/config-form", (req, res) => {
  try {
    const fs2 = require("fs");
    let cable = "usb", type = "usb", device = "", polltime = "10", battLevel = "30", minutes = "5";
    if (fs2.existsSync("/etc/apcupsd/apcupsd.conf")) {
      const content = fs2.readFileSync("/etc/apcupsd/apcupsd.conf", "utf8");
      const cm = content.match(/UPSCABLE\s+(\S+)/);
      if (cm) cable = cm[1];
      const tm = content.match(/UPSTYPE\s+(\S+)/);
      if (tm) type = tm[1];
      const dm = content.match(/DEVICE\s+(\S*)/);
      if (dm) device = dm[1];
      const pm = content.match(/POLLTIME\s+(\d+)/);
      if (pm) polltime = pm[1];
      const bm = content.match(/BATTERYLEVEL\s+(\d+)/);
      if (bm) battLevel = bm[1];
      const mm = content.match(/MINUTES\s+(\d+)/);
      if (mm) minutes = mm[1];
    }
    res.json({ success: true, cable, type, device, polltime, battLevel, minutes });
  } catch (e) {
    res.json({ success: true, cable: "usb", type: "usb", device: "", polltime: "10", battLevel: "30", minutes: "5" });
  }
});
module.exports = router;
