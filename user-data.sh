#!/bin/bash
set -e

# Palworld Dedicated Server Initialization Script
# This script runs on first boot to set up the server

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting Palworld Server Setup"
echo "========================================="

# Variables from Terraform
REGION="${region}"
PROJECT_NAME="${project_name}"
EIP_ALLOCATION_ID="${eip_allocation_id}"
DATA_VOLUME_ID="${data_volume_id}"
S3_BUCKET="${s3_bucket}"
SERVER_NAME="${server_name}"
SERVER_PASSWORD="${server_password}"
ADMIN_PASSWORD="${admin_password}"
MAX_PLAYERS="${max_players}"
BACKUP_CRON="${backup_cron_schedule}"
ENABLE_DASHBOARD="${enable_dashboard}"

MOUNT_POINT="/mnt/palworld-data"

# Get instance metadata using IMDSv2
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
AVAILABILITY_ZONE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null)

echo "Instance ID: $INSTANCE_ID"
echo "AZ: $AVAILABILITY_ZONE"

# Auto-detect EBS volume device name (handles both /dev/xvdf and NVMe naming)
# For NVMe instances, /dev/xvdf appears as /dev/nvme1n1
# Wait for the volume to appear and auto-detect its name
DEVICE_NAME=""
for possible_device in /dev/xvdf /dev/nvme1n1 /dev/nvme2n1; do
    if [ -e "$possible_device" ]; then
        DEVICE_NAME="$possible_device"
        break
    fi
done

if [ -z "$DEVICE_NAME" ]; then
    echo "Device not found yet, will wait..."
    DEVICE_NAME="/dev/nvme1n1"  # Default for NVMe instances
fi

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install AWS CLI and required tools
echo "Installing AWS CLI and tools..."
apt-get install -y \
    awscli \
    jq \
    unzip \
    curl \
    wget \
    htop \
    nvme-cli \
    ca-certificates \
    gnupg \
    lsb-release

# Associate Elastic IP
echo "Associating Elastic IP..."
aws ec2 associate-address \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$EIP_ALLOCATION_ID" \
    --region "$REGION" || echo "Failed to associate EIP (may already be associated)"

# Wait for EBS volume to be attached (Lambda should handle this)
echo "Waiting for data volume to be attached..."
MAX_WAIT=300
WAITED=0
while [ ! -e "$DEVICE_NAME" ] && [ $WAITED -lt $MAX_WAIT ]; do
    echo "Waiting for $DEVICE_NAME... ($WAITED seconds)"
    sleep 5
    WAITED=$((WAITED + 5))
done

if [ ! -e "$DEVICE_NAME" ]; then
    echo "ERROR: Data volume not attached after $MAX_WAIT seconds!"
    exit 1
fi

echo "Data volume found at $DEVICE_NAME"

# Check if volume is formatted
if ! blkid "$DEVICE_NAME"; then
    echo "Formatting new volume..."
    mkfs.ext4 "$DEVICE_NAME"
fi

# Create mount point and mount volume
echo "Mounting data volume..."
mkdir -p "$MOUNT_POINT"
mount "$DEVICE_NAME" "$MOUNT_POINT"

# Add to fstab for auto-mount on reboot
DEVICE_UUID=$(blkid -s UUID -o value "$DEVICE_NAME")
if ! grep -q "$DEVICE_UUID" /etc/fstab; then
    echo "UUID=$DEVICE_UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Create directory structure
mkdir -p "$MOUNT_POINT/palworld"
mkdir -p "$MOUNT_POINT/backups"

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Start Docker service
systemctl enable docker
systemctl start docker

# Create docker-compose file for Palworld
echo "Creating Palworld server configuration..."
cat > "$MOUNT_POINT/docker-compose.yml" <<EOF
version: '3.8'

services:
  palworld:
    image: thijsvanloef/palworld-server-docker:latest
    container_name: palworld-server
    restart: unless-stopped
    network_mode: host
    environment:
      - PUID=1000
      - PGID=1000
      - PORT=8211
      - PLAYERS=$MAX_PLAYERS
      - MULTITHREADING=true
      - RCON_ENABLED=true
      - RCON_PORT=25575
      - ADMIN_PASSWORD=$ADMIN_PASSWORD
      - SERVER_PASSWORD=$SERVER_PASSWORD
      - SERVER_NAME=$SERVER_NAME
      - COMMUNITY=true
      - PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
      - PUBLIC_PORT=8211
      - SERVER_DESCRIPTION=Dedicated Palworld server on AWS
      - UPDATE_ON_BOOT=true
      - BACKUP_ENABLED=true
      - BACKUP_CRON_EXPRESSION=0 */4 * * *
      - DELETE_OLD_BACKUPS=true
      - OLD_BACKUP_DAYS=3
    volumes:
      - $MOUNT_POINT/palworld:/palworld
    healthcheck:
      test: ["CMD", "bash", "-c", "printf 'GET / HTTP/1.1\n\n' > /dev/tcp/127.0.0.1/8211; exit $$?"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s
EOF

# Create systemd service for Palworld
echo "Creating systemd service..."
cat > /etc/systemd/system/palworld.service <<EOF
[Unit]
Description=Palworld Dedicated Server
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$MOUNT_POINT
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable palworld.service

# Download latest backup from S3 if exists
echo "Checking for existing backups in S3..."
LATEST_BACKUP=$(aws s3 ls s3://$S3_BUCKET/backups/ --region "$REGION" | sort | tail -n 1 | awk '{print $4}')

if [ ! -z "$LATEST_BACKUP" ]; then
    echo "Found backup: $LATEST_BACKUP - Restoring..."
    aws s3 sync "s3://$S3_BUCKET/backups/$LATEST_BACKUP" "$MOUNT_POINT/palworld/Pal/Saved" --region "$REGION"
fi

# Start Palworld server
echo "Starting Palworld server..."
systemctl start palworld.service

# Install CloudWatch Agent for metrics
echo "Installing CloudWatch Agent..."
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Configure CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "mem_used_percent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "disk_used_percent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      }
    },
    "append_dimensions": {
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
      "InstanceId": "$${aws:InstanceId}"
    }
  }
}
EOF

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Create backup script
cat > /usr/local/bin/backup-palworld.sh <<'BACKUP_SCRIPT'
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/palworld-backup-$TIMESTAMP"
S3_BUCKET="$S3_BUCKET"
REGION="$REGION"

echo "[$(date)] Starting backup to S3..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Copy game saves
if [ -d "$MOUNT_POINT/palworld/Pal/Saved" ]; then
    cp -r $MOUNT_POINT/palworld/Pal/Saved $BACKUP_DIR/

    # Upload to S3
    aws s3 sync $BACKUP_DIR s3://$S3_BUCKET/backups/$TIMESTAMP/ --region $REGION

    echo "[$(date)] Backup completed: s3://$S3_BUCKET/backups/$TIMESTAMP/"

    # Cleanup local backup
    rm -rf $BACKUP_DIR
else
    echo "[$(date)] No save data found to backup"
fi
BACKUP_SCRIPT

# Substitute variables in backup script
sed -i "s|\$S3_BUCKET|$S3_BUCKET|g" /usr/local/bin/backup-palworld.sh
sed -i "s|\$REGION|$REGION|g" /usr/local/bin/backup-palworld.sh
sed -i "s|\$MOUNT_POINT|$MOUNT_POINT|g" /usr/local/bin/backup-palworld.sh

chmod +x /usr/local/bin/backup-palworld.sh

# Add cron job for periodic backups
echo "Setting up periodic backups..."
(crontab -l 2>/dev/null; echo "$BACKUP_CRON /usr/local/bin/backup-palworld.sh >> /var/log/palworld-backup.log 2>&1") | crontab -

# Setup monitoring dashboard if enabled
if [ "$ENABLE_DASHBOARD" = "true" ]; then
    echo "Setting up monitoring dashboard..."

    # Install nginx
    apt-get install -y nginx

    # Create dashboard directory
    mkdir -p /var/www/dashboard

    # Create metrics API endpoint script
    cat > /usr/local/bin/palworld-metrics.sh <<'METRICS_SCRIPT'
#!/bin/bash

# Get system metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($MEM_USED/$MEM_TOTAL)*100}")

# Get player count via RCON
PLAYER_COUNT=0
if command -v docker &> /dev/null; then
    # Try to get player count from docker logs (simple method)
    PLAYER_COUNT=$(docker logs palworld-server 2>&1 | grep -i "player" | tail -1 | grep -oP '\d+(?= player)' || echo "0")
fi

# Output JSON
cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "cpu_percent": $CPU_USAGE,
  "memory_percent": $MEM_PERCENT,
  "memory_used_mb": $MEM_USED,
  "memory_total_mb": $MEM_TOTAL,
  "player_count": $PLAYER_COUNT,
  "max_players": $MAX_PLAYERS,
  "server_status": "running"
}
EOF
METRICS_SCRIPT

    sed -i "s|\$MAX_PLAYERS|$MAX_PLAYERS|g" /usr/local/bin/palworld-metrics.sh
    chmod +x /usr/local/bin/palworld-metrics.sh

    # Create nginx config
    cat > /etc/nginx/sites-available/dashboard <<'NGINX_CONFIG'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/dashboard;
    index index.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api/metrics {
        default_type application/json;
        content_by_lua_block {
            local handle = io.popen("/usr/local/bin/palworld-metrics.sh")
            local result = handle:read("*a")
            handle:close()
            ngx.say(result)
        }
    }

    # Simple CGI for metrics without lua
    location /metrics {
        add_header Content-Type application/json;
        alias /tmp/palworld-metrics.json;
    }
}
NGINX_CONFIG

    ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/default

    # Create cron to update metrics file every 30 seconds
    cat > /etc/systemd/system/palworld-metrics.service <<EOF
[Unit]
Description=Palworld Metrics Update

[Service]
Type=oneshot
ExecStart=/usr/local/bin/palworld-metrics.sh > /tmp/palworld-metrics.json
EOF

    cat > /etc/systemd/system/palworld-metrics.timer <<EOF
[Unit]
Description=Update Palworld Metrics Every 30 Seconds

[Timer]
OnBootSec=30
OnUnitActiveSec=30

[Install]
WantedBy=timers.target
EOF

    systemctl enable palworld-metrics.timer
    systemctl start palworld-metrics.timer

    # Create dashboard HTML
    cat > /var/www/dashboard/index.html <<'DASHBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Palworld Server Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 {
            text-align: center;
            color: white;
            margin-bottom: 30px;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .status-bar {
            background: white;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            display: flex;
            justify-content: space-around;
            align-items: center;
            flex-wrap: wrap;
        }
        .status-item { text-align: center; padding: 10px 20px; }
        .status-label {
            font-size: 0.9em;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .status-value {
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
            margin-top: 5px;
        }
        .status-online { color: #28a745; }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .metric-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .metric-title {
            font-size: 1.1em;
            color: #666;
            margin-bottom: 15px;
            font-weight: 600;
        }
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e9ecef;
            border-radius: 15px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        .progress-warning { background: linear-gradient(90deg, #ffa500, #ff6347); }
        .progress-danger { background: linear-gradient(90deg, #dc3545, #c82333); }
        .server-info {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #e9ecef;
        }
        .info-row:last-child { border-bottom: none; }
        .info-label { font-weight: 600; color: #666; }
        .info-value { color: #333; font-family: monospace; }
        .last-update {
            text-align: center;
            color: white;
            margin-top: 20px;
            opacity: 0.9;
        }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .pulse { animation: pulse 2s infinite; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎮 Palworld Server Dashboard</h1>
        <div id="loading" class="last-update pulse">Loading server metrics...</div>
        <div id="dashboard" style="display: none;">
            <div class="status-bar">
                <div class="status-item">
                    <div class="status-label">Status</div>
                    <div class="status-value status-online" id="server-status">● ONLINE</div>
                </div>
                <div class="status-item">
                    <div class="status-label">Players</div>
                    <div class="status-value" id="player-count">0 / 16</div>
                </div>
                <div class="status-item">
                    <div class="status-label">CPU</div>
                    <div class="status-value" id="cpu-display">0%</div>
                </div>
            </div>
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-title">CPU Usage</div>
                    <div class="progress-bar">
                        <div class="progress-fill" id="cpu-bar" style="width: 0%;">0%</div>
                    </div>
                </div>
                <div class="metric-card">
                    <div class="metric-title">Memory Usage</div>
                    <div class="progress-bar">
                        <div class="progress-fill" id="memory-bar" style="width: 0%;">0%</div>
                    </div>
                    <div style="margin-top: 10px; color: #666; font-size: 0.9em;" id="memory-details">-- MB / -- MB</div>
                </div>
            </div>
            <div class="server-info">
                <div class="metric-title">Server Information</div>
                <div class="info-row">
                    <span class="info-label">Server IP:</span>
                    <span class="info-value" id="server-ip">Loading...</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Game Port:</span>
                    <span class="info-value">8211 (UDP)</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Query Port:</span>
                    <span class="info-value">27015 (UDP)</span>
                </div>
            </div>
            <div class="last-update">Last updated: <span id="last-update-time">--</span></div>
        </div>
    </div>
    <script>
        async function updateMetrics() {
            try {
                const response = await fetch('/metrics');
                const data = await response.json();

                document.getElementById('loading').style.display = 'none';
                document.getElementById('dashboard').style.display = 'block';

                const cpuPercent = Math.round(data.cpu_percent || 0);
                const cpuBar = document.getElementById('cpu-bar');
                cpuBar.style.width = cpuPercent + '%';
                cpuBar.textContent = cpuPercent + '%';
                document.getElementById('cpu-display').textContent = cpuPercent + '%';

                cpuBar.className = 'progress-fill';
                if (cpuPercent > 90) cpuBar.classList.add('progress-danger');
                else if (cpuPercent > 70) cpuBar.classList.add('progress-warning');

                const memPercent = Math.round(data.memory_percent || 0);
                const memBar = document.getElementById('memory-bar');
                memBar.style.width = memPercent + '%';
                memBar.textContent = memPercent + '%';

                memBar.className = 'progress-fill';
                if (memPercent > 90) memBar.classList.add('progress-danger');
                else if (memPercent > 70) memBar.classList.add('progress-warning');

                document.getElementById('memory-details').textContent =
                    Math.round(data.memory_used_mb || 0) + ' MB / ' + Math.round(data.memory_total_mb || 0) + ' MB';

                document.getElementById('player-count').textContent =
                    (data.player_count || 0) + ' / ' + (data.max_players || 16);

                document.getElementById('last-update-time').textContent = new Date().toLocaleTimeString();
            } catch (error) {
                console.error('Error:', error);
            }
        }

        fetch('http://169.254.169.254/latest/meta-data/public-ipv4')
            .then(r => r.text())
            .then(ip => document.getElementById('server-ip').textContent = ip)
            .catch(() => document.getElementById('server-ip').textContent = window.location.hostname);

        updateMetrics();
        setInterval(updateMetrics, 30000);
    </script>
</body>
</html>
DASHBOARD_HTML

    systemctl restart nginx
fi

echo "========================================="
echo "Palworld Server Setup Complete!"
echo "========================================="
echo "Server will be ready in ~10 minutes"
echo "Monitor progress: journalctl -xu palworld -f"
echo "========================================="
