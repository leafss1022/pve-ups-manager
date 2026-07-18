const express = require('express');
const router = express.Router();
const { exec } = require('child_process');
const fs2 = require('fs');
const path = require('path');

// NUT configuration paths
const NUT_CONFIG_DIR = '/etc/nut';
const UPS_CONF = path.join(NUT_CONFIG_DIR, 'ups.conf');
const UPSD_CONF = path.join(NUT_CONFIG_DIR, 'upsd.conf');
const UPSD_USERS = path.join(NUT_CONFIG_DIR, 'upsd.users');
const UPSCONF_CONF = path.join(NUT_CONFIG_DIR, 'upsmon.conf');

// PVE UPS Manager settings directory
const SETTINGS_DIR = '/etc/pve-ups-manager';
const SETTINGS_FILE = path.join(SETTINGS_DIR, 'settings.json');

function loadSettings() {
  try {
    if (fs2.existsSync(SETTINGS_FILE)) {
      return JSON.parse(fs2.readFileSync(SETTINGS_FILE, 'utf8'));
    }
  } catch (e) { /* ignore */ }
  return {};
}

function saveSettings(settings) {
  if (!fs2.existsSync(SETTINGS_DIR)) fs2.mkdirSync(SETTINGS_DIR, { recursive: true });
  fs2.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2), 'utf8');
}

function getNutHost() {
  const s = loadSettings();
  return s.nutHost || process.env.NUT_HOST || 'localhost';
}

function getNutUps() {
  const s = loadSettings();
  return s.nutUps || process.env.NUT_UPS || 'ups';
}

// GET: Read NUT Config Files
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

// POST: Save NUT Config File
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

// POST: Validate NUT Config
router.post('/validate', (req, res) => {
  exec('nutconf -c 2>&1 || upscmd -l 2>&1 || echo "Validation done"', (err, stdout, stderr) => {
    res.json({ success: true, output: stdout || stderr || 'Validation completed (no output)' });
  });
});

// GET: UPS Status (supports remote NUT_HOST)
router.get('/status', (req, res) => {
  const nutHost = getNutHost();
  const nutUps = getNutUps();
  const target = nutUps + '@' + nutHost;
  exec('upsc ' + target + ' 2>&1', (err, stdout, stderr) => {
    // upsc outputs data to stdout on success, error to both stdout and stderr on failure
    const combined = (stdout || '') + (stderr || '');
    // Check if we got real UPS data (not an error message)
    const hasRealData = combined.length > 50 && 
      !combined.includes('Error') && 
      !combined.includes('failure') && 
      !combined.includes('not connected') &&
      !combined.includes('Connection refused');
    
    if (!hasRealData) {
      return res.json({ 
        success: false, 
        status: 'disconnected', 
        message: 'Cannot connect to NUT server at ' + target + '. Output: ' + combined.slice(0, 200),
        nutHost: nutHost,
        nutUps: nutUps
      });
    }
    
    const lines = combined.split('\n').filter(l => l.trim());
    const parsed = {};
    lines.forEach(line => {
      const idx = line.indexOf(':');
      if (idx > 0) {
        parsed[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
    });
    
    res.json({ success: true, status: 'connected', data: parsed, nutHost: nutHost });
  });
});

// GET/POST: NUT Connection Settings
router.get('/settings', (req, res) => {
  const settings = loadSettings();
  res.json({ success: true, nutHost: getNutHost(), nutUps: getNutUps(), settings });
});

router.post('/settings', (req, res) => {
  const { nutHost, nutUps } = req.body;
  try {
    const settings = loadSettings();
    if (nutHost !== undefined) settings.nutHost = nutHost;
    if (nutUps !== undefined) settings.nutUps = nutUps;
    saveSettings(settings);
    res.json({ success: true, message: 'NUT connection settings saved' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// POST: Restart NUT Services
router.post('/restart', (req, res) => {
  const nutHost = getNutHost();
  if (nutHost !== 'localhost') {
    exec('systemctl restart nut-client 2>&1 || service nut-client restart 2>&1 || echo "nut-client not found"', (err2, stdout2, stderr2) => {
      res.json({ success: !err2, message: err2 ? 'Restart attempted: ' + (stderr2 || err2.message) : 'nut-client restarted', output: stdout2 || stderr2 });
    });
  } else {
    const cmds = ['systemctl restart nut-server', 'systemctl restart nut-monitor', 'systemctl restart nut-client'];
    exec(cmds.join(' && '), (err, stdout, stderr) => {
      if (err) {
        exec('service nut-server restart && service nut-monitor restart', (err2, stdout2, stderr2) => {
          res.json({ success: !err2, message: err2 ? (err2.message || 'Restart failed') : 'Services restarted', output: stdout2 || stderr2 });
        });
      } else {
        res.json({ success: true, message: 'NUT services restarted', output: stdout || stderr });
      }
    });
  }
});



// POST: Save ups.conf from form fields
router.post("/ups-conf-form", (req, res) => {
  const { name, driver, port, desc } = req.body;
  if (!name || !driver) {
    return res.status(400).json({ success: false, message: "Missing required fields: name, driver" });
  }
  let conf = "[" + name + "]\n    driver = " + driver + "\n    port = " + (port || "auto");
  if (desc) conf += "\n    desc = \"" + desc + "\"";
  conf += "\n";
  try {
    fs2.writeFileSync(UPS_CONF, conf, "utf8");
    res.json({ success: true, message: "ups.conf saved" });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// GET: Parse ups.conf to form fields
router.get("/ups-conf-form", (req, res) => {
  try {
    let name = "ups", driver = "usbhid-ups", port = "auto", desc = "";
    if (fs2.existsSync(UPS_CONF)) {
      const content = fs2.readFileSync(UPS_CONF, "utf8");
      const nm = content.match(/^\[([^\]]+)\]/m);
      if (nm) name = nm[1].trim();
      const dr = content.match(/driver\s*=\s*(.+)/);
      if (dr) driver = dr[1].trim();
      const pt = content.match(/port\s*=\s*(.+)/);
      if (pt) port = pt[1].trim();
      const dc = content.match(/desc\s*=\s*\"?([^\"]+)\"?/);
      if (dc) desc = dc[1].trim();
    }
    res.json({ success: true, name, driver, port, desc });
  } catch (e) {
    res.json({ success: true, name: "ups", driver: "usbhid-ups", port: "auto", desc: "" });
  }
});

// POST: Save upsmon.conf from form fields
router.post("/upsmon-conf-form", (req, res) => {
  const { monitor, user, pass, role, warnat, pollfreq } = req.body;
  let conf = "MONITOR " + (monitor || "ups@localhost") + " 1 " + (user || "monuser") + " " + (pass || "secret") + " " + (role || "master") + "\n";
  conf += "SHUTDOWNCMD \"/sbin/shutdown -h +0\"\n";
  conf += "POLLFREQ " + (pollfreq || "5") + "\n";
  conf += "POLLFREQALERT 3\n";
  conf += "HOSTSYNC 15\n";
  conf += "WARNAT " + (warnat || "30") + "\n";
  conf += "DEADTIME 15\n";
  conf += "POWERDOWNFLAG /etc/killpower\n";
  try {
    fs2.writeFileSync(UPSCONF_CONF, conf, "utf8");
    res.json({ success: true, message: "upsmon.conf saved" });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// GET: Parse upsmon.conf to form fields
router.get("/upsmon-conf-form", (req, res) => {
  try {
    let monitor = "ups@localhost", user = "monuser", pass = "secret", role = "master", warnat = "30", pollfreq = "5";
    if (fs2.existsSync(UPSCONF_CONF)) {
      const content = fs2.readFileSync(UPSCONF_CONF, "utf8");
      const mm = content.match(/MONITOR\s+(\S+)\s+\d+\s+(\S+)\s+(\S+)\s+(\S+)/);
      if (mm) { monitor = mm[1]; user = mm[2]; pass = mm[3]; role = mm[4]; }
      const wm = content.match(/WARNAT\s+(\d+)/);
      if (wm) warnat = wm[1];
      const pm = content.match(/POLLFREQ\s+(\d+)/);
      if (pm) pollfreq = pm[1];
    }
    res.json({ success: true, monitor, user, pass, role, warnat, pollfreq });
  } catch (e) {
    res.json({ success: true, monitor: "ups@localhost", user: "monuser", pass: "secret", role: "master", warnat: "30", pollfreq: "5" });
  }
});

// POST: Save upsd.users from form fields
router.post("/upsd-users-form", (req, res) => {
  const { user, pass, role } = req.body;
  const content = "[" + (user || "monuser") + "]\n    password = " + (pass || "secret") + "\n    upsmon " + (role || "master") + "\n";
  try {
    fs2.writeFileSync(UPSD_USERS, content, "utf8");
    res.json({ success: true, message: "upsd.users saved" });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// GET: Parse upsd.users to form fields
router.get("/upsd-users-form", (req, res) => {
  try {
    let user = "monuser", pass = "secret", role = "master";
    if (fs2.existsSync(UPSD_USERS)) {
      const content = fs2.readFileSync(UPSD_USERS, "utf8");
      const um = content.match(/^\[([^\]]+)\]/m);
      if (um) user = um[1].trim();
      const pm = content.match(/password\s*=\s*(.+)/);
      if (pm) pass = pm[1].trim();
      const rm = content.match(/upsmon\s+(\S+)/);
      if (rm) role = rm[1].trim();
    }
    res.json({ success: true, user, pass, role });
  } catch (e) {
    res.json({ success: true, user: "monuser", pass: "secret", role: "master" });
  }
});
module.exports = router;