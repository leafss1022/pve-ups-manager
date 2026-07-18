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

    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
    });
});

const PORT = process.env.PORT || 13456;
server.listen(PORT, '0.0.0.0', () => {
    console.log('PVE UPS Manager running on http://0.0.0.0:' + PORT);
});
