const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const fs2 = require('fs');
const os = require('os');
const { exec } = require('child_process');

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
app.use('/api/diagnose', require('./routes/diagnose'));

// Serve frontend
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'frontend', 'public', 'index.html'));
});

function checkNUT(cb) {
    exec('which upsc 2>/dev/null && upsc ups@localhost 2>&1 || echo __NUT_NOT_FOUND__', (err, stdout) => {
        if (stdout && !stdout.includes('__NUT_NOT_FOUND__') && !stdout.includes('Error') && !stdout.includes('Connection failure')) {
            const np = {};
            stdout.split('\n').forEach(li => {
                const idx = li.indexOf(':');
                if (idx > 0) np[li.slice(0, idx).trim()] = li.slice(idx + 1).trim();
            });
            cb(true, np);
        } else {
            cb(false, {});
        }
    });
}

function checkAPC(cb) {
    exec('which apcaccess 2>/dev/null && apcaccess 2>&1 || echo __APC_NOT_FOUND__', (err, stdout) => {
        if (stdout && !stdout.includes('__APC_NOT_FOUND__') && !stdout.includes('Error') && !stdout.includes('Connection failure')) {
            const ap = {};
            stdout.split('\n').forEach(li => {
                const idx = li.indexOf(':');
                if (idx > 0) ap[li.slice(0, idx).trim()] = li.slice(idx + 1).trim();
            });
            cb(true, ap);
        } else {
            cb(false, {});
        }
    });
}

function checkPVE(cb) {
    exec('which qm 2>/dev/null && qm list 2>/dev/null | wc -l || echo 0', (err, stdout) => {
        const count = parseInt(stdout.trim()) || 0;
        cb(count > 1);
    });
}

var statusInterval = null;
io.on('connection', function(socket) {
    console.log('Client connected:', socket.id);
    
    var sendStatus = function() {
        checkNUT(function(nutOk, nutData) {
            if (nutOk) {
                socket.emit('nutStatus', { connected: true, data: nutData });
                socket.emit('activeTool', { tool: 'nut' });
            } else {
                checkAPC(function(apcOk, apcData) {
                    if (apcOk) {
                        socket.emit('apcStatus', { connected: true, data: apcData });
                        socket.emit('activeTool', { tool: 'apc' });
                    } else {
                        socket.emit('nutStatus', { connected: false, data: {} });
                        socket.emit('apcStatus', { connected: false, data: {} });
                        socket.emit('activeTool', { tool: 'none' });
                    }
                });
            }
        });
        
        checkPVE(function(pveOk) {
            socket.emit('pveStatus', { connected: pveOk });
        });
    };
    
    sendStatus();
    statusInterval = setInterval(sendStatus, 5000);
    
    socket.on('disconnect', function() {
        if (statusInterval) clearInterval(statusInterval);
        console.log('Client disconnected:', socket.id);
    });
});

const PORT = process.env.PORT || 13456;
server.listen(PORT, '0.0.0.0', () => {
    console.log('PVE UPS Manager v0.4.0 running on http://0.0.0.0:' + PORT);
});