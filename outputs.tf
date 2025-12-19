output "server_public_ip" {
  description = "Static public IP address of the Palworld server"
  value       = aws_eip.palworld.public_ip
}

output "server_password" {
  description = "Generated password for players to join the server"
  value       = random_password.server_password.result
  sensitive   = true
}

output "admin_password" {
  description = "Generated admin password for RCON and dashboard access"
  value       = random_password.admin_password.result
  sensitive   = true
}

output "server_connection_info" {
  description = "Connection information for the Palworld server"
  value = <<-EOT

    ========================================
    PALWORLD SERVER CONNECTION INFO
    ========================================

    Server IP:        ${aws_eip.palworld.public_ip}
    Game Port:        8211 (UDP)
    Query Port:       27015 (UDP)

    SSH Access:       ssh -i ${var.project_name}-key.pem ubuntu@${aws_eip.palworld.public_ip}
    Dashboard URL:    http://${aws_eip.palworld.public_ip}

    In-Game Connection:
    - Steam: Add server via Steam -> View -> Servers -> Favorites
    - IP: ${aws_eip.palworld.public_ip}:8211

    ⚠️  IMPORTANT: Get your passwords with these commands:

    Option 1 - Terraform Outputs:
    - Server Password:  terraform output -raw server_password
    - Admin Password:   terraform output -raw admin_password

    Option 2 - AWS Secrets Manager:
    - Passwords:        aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.palworld_passwords.name} --region ${var.aws_region}
    - SSH Private Key:  aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.ssh_private_key.name} --region ${var.aws_region}

    ========================================
    Server takes ~10 minutes to initialize after deployment
    Monitor progress: ssh in and run 'journalctl -xu palworld -f'
    ========================================
  EOT
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "backup_bucket_name" {
  description = "S3 bucket name for server backups"
  value       = aws_s3_bucket.backups.id
}

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret containing passwords"
  value       = aws_secretsmanager_secret.palworld_passwords.arn
}

output "secrets_manager_name" {
  description = "Name of the Secrets Manager secret containing passwords"
  value       = aws_secretsmanager_secret.palworld_passwords.name
}

output "ssh_key_secret_name" {
  description = "Name of the Secrets Manager secret containing SSH private key"
  value       = aws_secretsmanager_secret.ssh_private_key.name
}

output "ssh_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing SSH private key"
  value       = aws_secretsmanager_secret.ssh_private_key.arn
}

output "spot_cost_estimate" {
  description = "Estimated monthly cost for Spot instance"
  value       = "~$36/month (Spot pricing varies, $100 credits last ~2.8 months)"
}

output "ssh_access_info" {
  description = "SSH access configuration"
  value = var.restrict_ssh_to_current_ip ? {
    restriction = "enabled"
    allowed_ip  = local.current_ip_cidr
    note        = "SSH restricted to your current IP address"
  } : {
    restriction = "disabled"
    allowed_ip  = "0.0.0.0/0"
    note        = "SSH open to the internet - consider enabling restrict_ssh_to_current_ip"
  }
}
