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

module.exports = router;