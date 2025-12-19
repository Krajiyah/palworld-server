// Palworld Server Dashboard JavaScript
// Fetches and displays real-time server metrics

const REFRESH_INTERVAL = 30000; // 30 seconds
let startTime = Date.now();

// Fetch and update metrics
async function updateMetrics() {
    try {
        const response = await fetch('/metrics');

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        // Hide loading, show dashboard
        document.getElementById('loading').style.display = 'none';
        document.getElementById('dashboard').style.display = 'block';
        document.getElementById('error-message').style.display = 'none';

        // Update CPU
        const cpuPercent = Math.round(data.cpu_percent || 0);
        const cpuBar = document.getElementById('cpu-bar');
        cpuBar.style.width = `${cpuPercent}%`;
        cpuBar.textContent = `${cpuPercent}%`;

        // Color code based on usage
        cpuBar.className = 'progress-fill';
        if (cpuPercent > 90) {
            cpuBar.classList.add('progress-danger');
        } else if (cpuPercent > 70) {
            cpuBar.classList.add('progress-warning');
        }

        // Update Memory
        const memPercent = Math.round(data.memory_percent || 0);
        const memBar = document.getElementById('memory-bar');
        memBar.style.width = `${memPercent}%`;
        memBar.textContent = `${memPercent}%`;

        memBar.className = 'progress-fill';
        if (memPercent > 90) {
            memBar.classList.add('progress-danger');
        } else if (memPercent > 70) {
            memBar.classList.add('progress-warning');
        }

        // Update memory details
        const memUsed = Math.round(data.memory_used_mb || 0);
        const memTotal = Math.round(data.memory_total_mb || 0);
        document.getElementById('memory-details').textContent =
            `${memUsed} MB / ${memTotal} MB`;

        // Update player count
        const playerCount = data.player_count || 0;
        const maxPlayers = data.max_players || 16;
        document.getElementById('player-count').textContent =
            `${playerCount} / ${maxPlayers}`;

        // Update server status
        const statusElement = document.getElementById('server-status');
        if (data.server_status === 'running') {
            statusElement.textContent = '● ONLINE';
            statusElement.className = 'status-value status-online';
        } else {
            statusElement.textContent = '● OFFLINE';
            statusElement.className = 'status-value status-offline';
        }

        // Update uptime
        const uptime = calculateUptime(startTime);
        document.getElementById('uptime').textContent = uptime;

        // Update timestamp
        const now = new Date();
        document.getElementById('last-update-time').textContent =
            now.toLocaleTimeString();

    } catch (error) {
        console.error('Error fetching metrics:', error);

        // Show error message
        const errorMsg = document.getElementById('error-message');
        errorMsg.textContent = `Failed to fetch metrics: ${error.message}`;
        errorMsg.style.display = 'block';

        // Keep trying
        document.getElementById('loading').style.display = 'none';
    }
}

// Calculate uptime in human-readable format
function calculateUptime(startTimestamp) {
    const uptime = Date.now() - startTimestamp;
    const seconds = Math.floor(uptime / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) {
        return `${days}d ${hours % 24}h`;
    } else if (hours > 0) {
        return `${hours}h ${minutes % 60}m`;
    } else if (minutes > 0) {
        return `${minutes}m`;
    } else {
        return `${seconds}s`;
    }
}

// Get server IP from metadata
async function getServerIP() {
    try {
        // Try to fetch public IP from server's own endpoint
        const response = await fetch('http://169.254.169.254/latest/meta-data/public-ipv4');
        const ip = await response.text();
        document.getElementById('server-ip').textContent = ip;
    } catch (error) {
        // Fallback to window location
        document.getElementById('server-ip').textContent = window.location.hostname;
    }
}

// Initialize dashboard
async function init() {
    await getServerIP();
    await updateMetrics();

    // Refresh metrics periodically
    setInterval(updateMetrics, REFRESH_INTERVAL);
}

// Start when page loads
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
