const fs = require("fs");
const b = "C:\\Users\\44853\\Documents\\pve-ups";

// 3. Fix app.js - upgrade WebSocket to push actual UPS status
let app = fs.readFileSync(b + "\\backend\\app.js", "utf8");

const oldWS = `// WebSocket for real-time UPS monitoring
io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);

    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
    });
});`;

const newWS = `// WebSocket for real-time UPS monitoring
io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);

    // Periodically push UPS status to the connected client
    const pushInterval = setInterval(() => {
        const { exec } = require('child_process');
        const fs2 = require('fs');
        const SETTINGS = '/etc/pve-ups-manager/settings.json';
        let nutHost = process.env.NUT_HOST || 'localhost';
        let nutUps = process.env.NUT_UPS || 'ups';
        try {
            if (fs2.existsSync(SETTINGS)) {
                const s = JSON.parse(fs2.readFileSync(SETTINGS, 'utf8'));
                if (s.nutHost) nutHost = s.nutHost;
                if (s.nutUps) nutUps = s.nutUps;
            }
        } catch(e) {}
        exec('upsc ' + nutUps + '@' + nutHost + ' 2>&1', { timeout: 5000 }, (err, stdout, stderr) => {
            const data = {};
            const combined = (stdout || '') + (stderr || '');
            const lines = combined.split('\\n').filter(l => l.trim());
            lines.forEach(line => {
                const idx = line.indexOf(':');
                if (idx > 0) {
                    data[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
                }
            });
            const connected = !combined.includes('Error') && Object.keys(data).length > 0;
            socket.emit('ups-status', { connected, data, timestamp: Date.now() });
            // Also push system info
            if (socket._firstPush) {
                try {
                    socket.emit('system-info', {
                        hostname: require('os').hostname(),
                        uptime: require('os').uptime(),
                        cpus: require('os').cpus().length,
                        totalMem: require('os').totalmem(),
                        freeMem: require('os').freemem()
                    });
                } catch(e) {}
                socket._firstPush = false;
            }
        });
    }, 10000);

    socket._firstPush = true;

    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
        clearInterval(pushInterval);
    });
});`;

app = app.replace(oldWS, newWS);
fs.writeFileSync(b + "\\backend\\app.js", app, "utf8");
console.log("app.js: WebSocket now pushes real UPS status");

// 4. Fix index.html - remove checkUps double-polling, add WebSocket listener
let html = fs.readFileSync(b + "\\frontend\\public\\index.html", "utf8");

// Replace the v0.5.0 version badge
html = html.replace(/v0\.5\.0/g, "v0.6.0");

// Fix the checkTools function to only check local tools (not connection)
const oldCheckTools = html.match(/function checkTools\(\)\{[\s\S]+?\n\}/);
if (oldCheckTools) {
    console.log("Found checkTools function");
}
const oldCheckUps = html.match(/function checkUps\(\)\{[\s\S]+?\n\}/);
if (oldCheckUps) {
    console.log("Found checkUps function");
}

// Add WebSocket connection
const wsScript = `
// WebSocket connection for real-time updates
let wsConnected = false;
function connectWebSocket() {
    const ws = new WebSocket((window.location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + window.location.host);
    ws.onopen = () => {
        wsConnected = true;
        document.getElementById('connSt').className = 'bdg ok';
        document.getElementById('connSt').innerHTML = '● 已连接';
        log('WebSocket 已连接', 'ok');
    };
    ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'ups-status') {
                updateUpsUI(msg.data);
                checkTools();
            } else if (msg.type === 'system-info') {
                updateSysInfo(msg.data);
            }
        } catch(e) {}
    };
    ws.onclose = () => {
        wsConnected = false;
        document.getElementById('connSt').className = 'bdg no';
        document.getElementById('connSt').innerHTML = '\\u2715 未连接';
        setTimeout(connectWebSocket, 5000);
    };
    ws.onerror = () => { ws.close(); };
}
`;

// Insert WebSocket function + DOMContentLoaded update
const domLoadedMatch = html.match(/document\.addEventListener\("DOMContentLoaded",function\(\)\{[\s\S]+?\}\)/);
if (domLoadedMatch) {
    const oldDOM = domLoadedMatch[0];
    const newDOM = `document.addEventListener("DOMContentLoaded",function(){
checkTools();connectWebSocket();
setInterval(function(){checkTools();},30000);
log("仪表板就绪","ok")})`;
    html = html.replace(oldDOM, newDOM);
}

// Remove setInterval-based polling from DOMContentLoaded (we replaced it above)
// Replace the DOMContentLoaded to use WebSocket instead of polling

// Add the wsScript before the closing script tag
html = html.replace('</script>', wsScript + '\n</script>');

fs.writeFileSync(b + '\\frontend\\public\\index.html', html, 'utf8');
console.log("index.html: WebSocket support + v0.6.0");