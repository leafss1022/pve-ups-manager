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
app.use('/api/diagnose', require('./routes/diagnose'));

// Serve frontend
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'frontend', 'public', 'index.html'));
});

// WebSocket
var statusInterval = null;
io.on('connection', function(socket) {
    console.log('Client connected:', socket.id);
    var sendStatus = function() {
        var exec = require('child_process').exec;
        exec('upsc ups@localhost 2>&1', function(err, stdout) {
            var np = {};
            if (!err && stdout && !stdout.includes('Error')) {
                stdout.split('\n').forEach(function(li) {
                    var idx = li.indexOf(':');
                    if (idx > 0) np[li.slice(0, idx).trim()] = li.slice(idx + 1).trim();
                });
            }
            socket.emit('nutStatus', { connected: Object.keys(np).length > 0, data: np });
        });
        exec('apcaccess 2>&1', function(err2, stdout2) {
            var ap = {};
            if (!err2 && stdout2 && !stdout2.includes('Error')) {
                stdout2.split('\n').forEach(function(li) {
                    var idx = li.indexOf(':');
                    if (idx > 0) ap[li.slice(0, idx).trim()] = li.slice(idx + 1).trim();
                });
            }
            socket.emit('apcStatus', { connected: Object.keys(ap).length > 0, data: ap });
        });
    };
    sendStatus();
    statusInterval = setInterval(sendStatus, 5000);
    socket.on('disconnect', function() {
        if (statusInterval) clearInterval(statusInterval);
        console.log('Client disconnected:', socket.id);
    });
});

const PORT = process.env.PORT || 3456;
server.listen(PORT, '0.0.0.0', () => {
    console.log('PVE UPS Manager running on http://0.0.0.0:' + PORT);
});