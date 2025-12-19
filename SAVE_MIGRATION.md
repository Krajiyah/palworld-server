# Migrating Existing Palworld Saves to Dedicated Server

This guide explains how to transfer your existing Palworld save data from your Windows gaming desktop (Steam) to your new AWS dedicated server, so you can continue your progress.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Migration](#quick-migration)
- [Detailed Step-by-Step](#detailed-step-by-step)
- [Troubleshooting](#troubleshooting)
- [Important Notes](#important-notes)

## Prerequisites

- Access to your Windows gaming desktop with existing Palworld saves
- SSH access to your AWS server
- `palworld-server-key.pem` file
- Server IP address
- WinSCP, FileZilla, or command-line SCP tool

## Quick Migration

```bash
# 1. On Windows, locate your save files:
C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\<SteamID>\<WorldID>\

# 2. Copy entire save folder to server:
scp -i palworld-server-key.pem -r "C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\<SteamID>" ubuntu@<SERVER_IP>:/tmp/

# 3. SSH into server and move saves:
ssh -i palworld-server-key.pem ubuntu@<SERVER_IP>
sudo cp -r /tmp/<SteamID>/* /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/
sudo chown -R 1000:1000 /mnt/palworld-data/palworld/Pal/Saved/
sudo systemctl restart palworld

# 4. Done! Your world is now on the dedicated server
```

## Detailed Step-by-Step

### Step 1: Locate Your Save Files on Windows

1. **Open File Explorer** and navigate to:
   ```
   C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\
   ```

   **Tip**: If you can't see `AppData`, enable "Show hidden files":
   - File Explorer → View → Options → View tab
   - Check "Show hidden files, folders, and drives"

2. **Find your Steam ID folder** (long number like `76561198012345678`)
   ```
   C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\76561198012345678\
   ```

3. **Find your World ID folder** (random GUID like `A1B2C3D4E5F6...`)
   ```
   C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\76561198012345678\A1B2C3D4E5F6.../
   ```

   This folder contains:
   - `Level.sav` - Your world data
   - `LevelMeta.sav` - World metadata
   - `LocalData.sav` - Local player data
   - `Players/` folder - Player save files
   - `backup/` folder - Auto-backups

4. **Important**: Note down these paths:
   ```
   Steam ID: 76561198012345678
   World ID: A1B2C3D4E5F6...
   Full Path: C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\76561198012345678\A1B2C3D4E5F6.../
   ```

### Step 2: Create a Backup (Recommended)

Before migrating, create a backup:

**On Windows:**
```powershell
# Create backup folder
mkdir C:\Palworld-Backup

# Copy your entire save folder
xcopy "C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\76561198012345678" C:\Palworld-Backup\ /E /I /H

# Create a zip for safekeeping
# Right-click the backup folder → "Send to" → "Compressed (zipped) folder"
```

### Step 3: Transfer Saves to Server

You have three options:

#### Option A: Using WinSCP (Easiest for Windows users)

1. **Download and install WinSCP**: https://winscp.net/

2. **Connect to your server**:
   - File protocol: `SFTP`
   - Host name: `<SERVER_IP>`
   - Port: `22`
   - User name: `ubuntu`
   - Password: (leave empty)
   - Advanced → SSH → Authentication → Private key file: Browse to `palworld-server-key.pem`

3. **Transfer files**:
   - Left panel (Windows): Navigate to `C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\<SteamID>\`
   - Right panel (Server): Navigate to `/tmp/`
   - Drag your `<WorldID>` folder from left to right

#### Option B: Using SCP from Windows (Command Line)

**Using Windows PowerShell or Command Prompt:**

```powershell
# Navigate to where your .pem key is stored
cd C:\path\to\palworld-server\

# Copy your save folder to server
scp -i palworld-server-key.pem -r "C:\Users\<YourUsername>\AppData\Local\Pal\Saved\SaveGames\<SteamID>\<WorldID>" ubuntu@<SERVER_IP>:/tmp/palworld-save/
```

#### Option C: Using FileZilla

1. **Download FileZilla**: https://filezilla-project.org/

2. **Configure SFTP connection**:
   - Host: `sftp://<SERVER_IP>`
   - Username: `ubuntu`
   - Password: (leave empty)
   - Port: `22`
   - Edit → Settings → Connection → SFTP → Add key file → Select `palworld-server-key.pem`

3. **Transfer**:
   - Local site (left): Navigate to your save folder
   - Remote site (right): Navigate to `/tmp/`
   - Drag folder from left to right

### Step 4: SSH into Server and Place Saves

```bash
# Connect to server
ssh -i palworld-server-key.pem ubuntu@<SERVER_IP>

# Check if server is running
docker ps | grep palworld

# Stop the server temporarily
sudo systemctl stop palworld

# Create target directory if it doesn't exist
sudo mkdir -p /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/

# Copy the save files
# Replace <WorldID> with your actual World ID folder name
sudo cp -r /tmp/palworld-save/<WorldID> /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/

# Verify files were copied
ls -la /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/<WorldID>/

# Set correct ownership (Docker container runs as user 1000:1000)
sudo chown -R 1000:1000 /mnt/palworld-data/palworld/Pal/Saved/

# Set correct permissions
sudo chmod -R 755 /mnt/palworld-data/palworld/Pal/Saved/

# Clean up temporary files
rm -rf /tmp/palworld-save/

# Start the server
sudo systemctl start palworld

# Watch logs to ensure it starts correctly
docker logs palworld-server -f
```

Look for lines like:
```
World loading completed
Server is ready
```

Press `Ctrl+C` to exit log view.

### Step 5: Connect and Verify

1. **Open Palworld on your gaming PC**

2. **Join your server**:
   - IP: `<SERVER_IP>:8211`
   - Password: `terraform output -raw server_password`

3. **Check your progress**:
   - You should spawn in your existing world
   - All your bases, Pals, and items should be intact
   - Other players can now join your world!

## Troubleshooting

### "I joined but I'm in a new world, not my old one"

**Cause**: The server is using a different save file.

**Solution**:
```bash
ssh -i palworld-server-key.pem ubuntu@<SERVER_IP>

# Check what worlds exist
ls -la /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/

# You should see your <WorldID> folder
# If not, the copy didn't work - repeat Step 4

# Check server configuration
docker exec palworld-server env | grep -i world
```

### "Permission denied" errors

```bash
# Fix permissions
sudo chown -R 1000:1000 /mnt/palworld-data/palworld/Pal/Saved/
sudo chmod -R 755 /mnt/palworld-data/palworld/Pal/Saved/

# Restart server
sudo systemctl restart palworld
```

### "Server won't start after migration"

```bash
# Check Docker logs
docker logs palworld-server --tail 100

# Common issues:
# 1. Corrupted save file - restore from backup
# 2. Wrong permissions - run chown commands above
# 3. Incompatible save version - check game version matches

# Restore from backup if needed
sudo rm -rf /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/<WorldID>
# Then re-copy from Windows backup
```

### "My character is missing/reset"

**Cause**: Player data not transferred correctly.

**Solution**:
```bash
# Ensure you copied the Players folder
ls -la /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/<WorldID>/Players/

# If empty, re-copy from Windows:
# 1. Copy Players folder from Windows save
# 2. SCP to server
# 3. Move to correct location
# 4. Fix permissions
sudo chown -R 1000:1000 /mnt/palworld-data/palworld/Pal/Saved/
```

### "Multiple worlds exist - which one is mine?"

```bash
# List all worlds
ls -lah /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/

# Check world creation dates
find /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/ -name "Level.sav" -exec ls -lh {} \;

# Your migrated world should have the most recent modification date from Windows
```

## Important Notes

### World ID Changes

- **Dedicated servers use a fixed "Player ID" of `0`** instead of your Steam ID
- Your world will be in: `/mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/<WorldID>/`
- Original Windows path: `C:\Users\...\SaveGames\<SteamID>\<WorldID>/`
- The `<WorldID>` (GUID) stays the same, but parent folder changes from `<SteamID>` to `0`

### What Gets Migrated

✅ **Migrated:**
- World terrain and structures
- Your bases and buildings
- All your Pals (captured and in bases)
- Storage chests and their contents
- Technology unlocks
- Player level and stats
- Quest progress

❌ **NOT Migrated (multiplayer-specific):**
- Guild/team associations (will need to recreate)
- Some multiplayer settings

### Steam ID vs Dedicated Server

**Steam (Single Player/Co-op):**
```
SaveGames/
└── 76561198012345678/     (Your Steam ID)
    └── A1B2C3D4...        (World ID)
        ├── Level.sav
        ├── Players/
        └── ...
```

**Dedicated Server:**
```
SaveGames/
└── 0/                     (Fixed ID for dedicated servers)
    └── A1B2C3D4...        (Same World ID)
        ├── Level.sav
        ├── Players/
        └── ...
```

### Backup Strategy Going Forward

After migration, your saves are backed up automatically:

1. **EBS Volume**: Persistent, survives server restarts
2. **S3 Backups**: Every 6 hours via cron
3. **Manual backups**: Run `/usr/local/bin/backup-palworld.sh`

**Download backups to Windows**:
```bash
# List backups
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/backups/ --region us-west-1

# Download a specific backup
aws s3 cp s3://BUCKET-NAME/backups/20250115_120000/ C:\Palworld-Server-Backups\ --recursive --region us-west-1
```

### Version Compatibility

**Important**: Your Windows game version and server version must match!

- Check your Windows game version: Steam → Library → Palworld → Properties → Updates
- Server updates automatically on restart (if `UPDATE_ON_BOOT=true` in docker-compose)

If you get "version mismatch" errors:
1. Update your Windows game via Steam
2. Restart the server: `sudo systemctl restart palworld`

## Alternative: Fresh Start on Server

If migration fails or you want a clean start:

```bash
# SSH into server
ssh -i palworld-server-key.pem ubuntu@<SERVER_IP>

# Remove all saves
sudo systemctl stop palworld
sudo rm -rf /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/*
sudo systemctl start palworld

# Server will create a fresh world
# You can still keep your Windows saves for solo play
```

## Questions?

- **Can I play solo and multiplayer simultaneously?**
  Yes! Your Windows saves are separate from server saves. You can keep both.

- **What if I made progress on Windows after migration?**
  You'll need to migrate again, or start fresh on the server. Choose one as your "main" save.

- **Can I migrate back to Windows later?**
  Yes! Reverse the process - copy from server's `/mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/<WorldID>/` back to Windows `<SteamID>/<WorldID>/`.

---

**Your saves are now migrated to the dedicated server!** Your friends can join and continue the adventure with you. 🎮
