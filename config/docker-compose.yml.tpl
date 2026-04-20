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
      - PLAYERS=${max_players}
      - MULTITHREADING=true
      - RCON_ENABLED=true
      - RCON_PORT=25575
      - ADMIN_PASSWORD=${admin_password}
      - SERVER_PASSWORD=${server_password}
      - SERVER_NAME=${server_name}
      - COMMUNITY=true
      - PUBLIC_IP=${public_ip}
      - PUBLIC_PORT=8211
      - SERVER_DESCRIPTION=Dedicated Palworld server on AWS
      - UPDATE_ON_BOOT=false
      - BACKUP_ENABLED=true
      - BACKUP_CRON_EXPRESSION=0 */4 * * *
      - DELETE_OLD_BACKUPS=true
      - OLD_BACKUP_DAYS=3
      - TZ=America/Los_Angeles
      - ALLOW_GLOBAL_PALBOX_IMPORT=true
      - BASE_CAMP_WORKER_MAX_NUM=${base_camp_worker_max_num}
      - BASE_CAMP_MAX_NUM_IN_GUILD=${base_camp_max_num_in_guild}
    volumes:
      - /mnt/palworld-data/palworld:/palworld
