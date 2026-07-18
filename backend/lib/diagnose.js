const { exec } = require('child_process');
const fs2 = require('fs');
const path2 = require('path');
const os = require('os');

var ND = '/etc/nut';
var AD = '/etc/apcupsd';

function run(cmd) {
  return new Promise(function(resolve) {
    exec(cmd, { timeout: 10000 }, function(err, stdout, stderr) {
      resolve({ code: err ? -1 : 0, stdout: (stdout||'').trim(), stderr: (stderr||'').trim() });
    });
  });
}

function fx(p) { try { return fs2.existsSync(p) && fs2.statSync(p).isFile(); } catch(e) { return false; } }
function dx(p) { try { return fs2.existsSync(p) && fs2.statSync(p).isDirectory(); } catch(e) { return false; } }

async function dn() {
  var r = { installed: false, services: {}, configs: {}, upsc: null, errors: [] };
  var w = await run('which upsc upsd upsmon nut-server 2>&1');
  r.installed = w.stdout.includes('upsc');
  if (!r.installed) r.errors.push('NUT not installed');
  for (var si=0; si<3; si++) {
    var svc = ['nut-server','nut-monitor','nut-client'][si];
    var st = await run('systemctl is-active ' + svc + ' 2>&1');
    r.services[svc] = st.stdout.trim();
  }
  for (var fi=0; fi<4; fi++) {
    var fn = ['ups.conf','upsd.conf','upsd.users','upsmon.conf'][fi];
    r.configs[fn] = fx(path2.join(ND, fn));
  }
  var u = await run('upsc ups@localhost 2>&1');
  if (u.code===0 && u.stdout && !u.stdout.includes('Error')) { r.upsc={connected:true}; }
  else { r.upsc={connected:false}; r.errors.push('upsc failed'); }
  return r;
}

async function da() {
  var r = { installed: false, services: {}, config: false, apcaccess: null, errors: [] };
  var w = await run('which apcupsd apcaccess 2>&1');
  r.installed = w.stdout.includes('apcupsd');
  if (!r.installed) r.errors.push('apcupsd not installed');
  var st = await run('systemctl is-active apcupsd 2>&1');
  r.services.apcupsd = st.stdout.trim();
  r.config = fx(path2.join(AD, 'apcupsd.conf'));
  var a = await run('apcaccess 2>&1');
  if (a.code===0 && a.stdout && !a.stdout.includes('Error')) { r.apcaccess={connected:true}; }
  else { r.apcaccess={connected:false}; r.errors.push('apcaccess failed'); }
  return r;
}

async function dp() {
  var r = { isPVE: false, version: null, commands: {}, errors: [] };
  var v = await run('cat /etc/pve/version 2>&1');
  r.isPVE = v.code===0 && v.stdout && !v.stdout.includes('No such');
  if (r.isPVE) r.version = v.stdout.trim();
  var cmds = ['qm','pct','pvesh','pveversion'];
  for (var ci=0; ci<cmds.length; ci++) {
    var w2 = await run('which ' + cmds[ci] + ' 2>&1');
    r.commands[cmds[ci]] = w2.code===0;
  }
  var dc = await run('cat /proc/1/cgroup 2>/dev/null | grep -q docker && echo true || echo false');
  r.inDocker = dc.stdout==='true';
  if (r.inDocker) r.errors.push('In Docker');
  return r;
}

async function ds() {
  var r = { hostname: os.hostname(), platform: os.platform(), arch: os.arch(), cpus: os.cpus().length, node: process.version };
  var w = await run('whoami 2>&1');
  r.whoami = w.stdout.trim();
  r.paths = { nut: dx(ND), apc: dx(AD), pve: dx('/etc/pve'), opt: dx('/opt/pve-ups-manager') };
  return r;
}

async function runFullDiagnose() {
  var t0 = Date.now();
  var r = { ts: new Date().toISOString(), system: await ds(), pve: await dp(), nut: await dn(), apc: await da(), elapsed: Date.now()-t0 };
  var errs = [];
  var keys = ['nut','apc','pve'];
  for (var ki=0; ki<keys.length; ki++) {
    if (r[keys[ki]].errors) {
      for (var ej=0; ej<r[keys[ki]].errors.length; ej++) {
        errs.push(keys[ki] + ': ' + r[keys[ki]].errors[ej]);
      }
    }
  }
  r.summary = { count: errs.length, list: errs, ok: errs.length===0 };
  return r;
}

module.exports = { runFullDiagnose, dn, da, dp, ds };