const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const fs2 = require('fs');
const os = require('os');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] }
});

app.use(express.json());
app.use(express.static(path.join(__dirname, '..', 'frontend', 'public')));

// Routes
app.use('/api/nut', require('./routes/nut'));
app.use('/api/apcupsd', require('./routes/apcupsd'));
app.use('/api/pve', require('./routes/pve'));
app.use('/api/system', require('./routes/system'));

// Serve frontend
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'frontend', 'public', 'index.html'));
});

// WebSocket for real-time UPS monitoring
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
            const lines = combined.split('\n').filter(l => l.trim());
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
});

const PORT = process.env.PORT || 3456;
server.listen(PORT, '0.0.0.0', () => {
    console.log('PVE UPS Manager running on http://0.0.0.0:' + PORT);
});
