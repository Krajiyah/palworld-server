# PalWorld Settings Configuration Sync
# This file manages the automatic synchronization of PalWorldSettings.ini and docker-compose.yml to the server

# Generate the PalWorldSettings.ini from template
resource "local_file" "palworld_settings" {
  filename = "${path.module}/config/PalWorldSettings.ini"
  content = templatefile("${path.module}/config/PalWorldSettings.ini.tpl", {
    # Dynamic values from Terraform
    admin_password              = random_password.admin_password.result
    server_password             = random_password.server_password.result
    public_ip                   = aws_eip.palworld.public_ip
    max_players                 = var.palworld_max_players
    server_name                 = var.palworld_server_name
    base_camp_max_num_in_guild  = var.palworld_base_camp_max_num_in_guild
    base_camp_worker_max_num    = var.palworld_base_camp_worker_max_num
  })

  file_permission = "0644"
}

# Generate docker-compose.yml from template
resource "local_file" "docker_compose" {
  filename = "${path.module}/config/docker-compose.yml"
  content = templatefile("${path.module}/config/docker-compose.yml.tpl", {
    admin_password              = random_password.admin_password.result
    server_password             = random_password.server_password.result
    public_ip                   = aws_eip.palworld.public_ip
    max_players                 = var.palworld_max_players
    server_name                 = var.palworld_server_name
    base_camp_max_num_in_guild  = var.palworld_base_camp_max_num_in_guild
    base_camp_worker_max_num    = var.palworld_base_camp_worker_max_num
  })

  file_permission = "0644"
}

# Sync settings to server when file changes
resource "null_resource" "sync_palworld_settings" {
  # Trigger when config files change or force_update is incremented
  triggers = {
    settings_hash       = local_file.palworld_settings.content_md5
    docker_compose_hash = local_file.docker_compose.content_md5
    force_update        = var.palworld_force_update
  }

  # Wait for the ASG to have an instance
  depends_on = [aws_autoscaling_group.palworld]

  # Copy the settings file to the server
  provisioner "file" {
    source      = local_file.palworld_settings.filename
    destination = "/tmp/PalWorldSettings.ini"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.palworld_ssh.private_key_openssh
      host        = aws_eip.palworld.public_ip
      timeout     = "5m"
    }
  }

  # Copy docker-compose.yml to the server
  provisioner "file" {
    source      = local_file.docker_compose.filename
    destination = "/tmp/docker-compose.yml"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.palworld_ssh.private_key_openssh
      host        = aws_eip.palworld.public_ip
      timeout     = "5m"
    }
  }

  # Deploy configs and restart service
  provisioner "remote-exec" {
    inline = [
      "echo 'Syncing Palworld configuration...'",
      "echo 'Deploying docker-compose.yml...'",
      "sudo cp /tmp/docker-compose.yml /mnt/palworld-data/docker-compose.yml",
      "sudo chown ubuntu:ubuntu /mnt/palworld-data/docker-compose.yml",
      "rm /tmp/docker-compose.yml",
      "echo 'Deploying PalWorldSettings.ini...'",
      "sudo mkdir -p /mnt/palworld-data/palworld/Pal/Saved/Config/LinuxServer",
      "sudo cp /tmp/PalWorldSettings.ini /mnt/palworld-data/palworld/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini",
      "sudo chown -R 1000:1000 /mnt/palworld-data/palworld/Pal/Saved/Config/LinuxServer",
      "rm /tmp/PalWorldSettings.ini",
      "echo 'Deleting WorldOption.sav to refresh cached settings...'",
      "sudo rm -f /mnt/palworld-data/palworld/Pal/Saved/SaveGames/0/*/WorldOption.sav || true",
      "echo 'Pulling latest Palworld Docker image...'",
      "cd /mnt/palworld-data && sudo docker compose pull",
      "echo 'Stopping server for update...'",
      "cd /mnt/palworld-data && sudo docker compose down || true",
      "echo 'Temporarily enabling UPDATE_ON_BOOT for game file update...'",
      "sudo sed -i 's/UPDATE_ON_BOOT=false/UPDATE_ON_BOOT=true/' /mnt/palworld-data/docker-compose.yml",
      "echo 'Starting server with game file update enabled (this may take a few minutes)...'",
      "cd /mnt/palworld-data && sudo docker compose up -d",
      "echo 'Waiting for server to become healthy (update in progress)...'",
      "timeout 300 bash -c 'until docker inspect --format=\"{{.State.Health.Status}}\" palworld-server 2>/dev/null | grep -q healthy; do echo \"Waiting for update to complete...\"; sleep 15; done' || echo 'Timeout waiting for health check'",
      "echo 'Reverting UPDATE_ON_BOOT to false for future restarts...'",
      "sudo sed -i 's/UPDATE_ON_BOOT=true/UPDATE_ON_BOOT=false/' /mnt/palworld-data/docker-compose.yml",
      "echo 'Update complete! Server running with latest version.'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.palworld_ssh.private_key_openssh
      host        = aws_eip.palworld.public_ip
      timeout     = "5m"
    }
  }
}
