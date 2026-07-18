var express = require('express');
var router = express.Router();
var diag = require('./lib/diagnose');

router.get('/full', async function(req, res) {
  try {
    var result = await diag.runFullDiagnose();
    res.json({ success: true, diagnose: result });
  } catch(e) {
    res.json({ success: false, message: e.message });
  }
});

router.get('/nut', async function(req, res) {
  try {
    var result = await diag.dn();
    res.json({ success: true, diagnose: result });
  } catch(e) {
    res.json({ success: false, message: e.message });
  }
});

router.get('/apc', async function(req, res) {
  try {
    var result = await diag.da();
    res.json({ success: true, diagnose: result });
  } catch(e) {
    res.json({ success: false, message: e.message });
  }
});

router.get('/pve', async function(req, res) {
  try {
    var result = await diag.dp();
    res.json({ success: true, diagnose: result });
  } catch(e) {
    res.json({ success: false, message: e.message });
  }
});

router.get('/system', async function(req, res) {
  try {
    var result = await diag.ds();
    res.json({ success: true, diagnose: result });
  } catch(e) {
    res.json({ success: false, message: e.message });
  }
});

module.exports = router;