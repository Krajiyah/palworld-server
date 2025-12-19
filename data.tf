# Data sources for dynamic values

# Get current public IP address (the machine running Terraform)
data "external" "current_ip" {
  program = ["bash", "-c", "curl -s https://ifconfig.me && echo"]

  # Only fetch if SSH restriction is enabled
  count = var.restrict_ssh_to_current_ip ? 1 : 0
}

# Alternative: Use http data source (doesn't require curl)
data "http" "current_ip" {
  url = "https://ifconfig.me/ip"

  # Only fetch if SSH restriction is enabled
  count = var.restrict_ssh_to_current_ip ? 1 : 0
}

# Use http data source as primary (more reliable, no external dependencies)
locals {
  current_ip_cidr = var.restrict_ssh_to_current_ip ? "${trimspace(data.http.current_ip[0].response_body)}/32" : null

  # SSH allowed CIDR blocks
  ssh_allowed_cidrs = var.restrict_ssh_to_current_ip ? [local.current_ip_cidr] : ["0.0.0.0/0"]

  # RCON allowed CIDR blocks (same as SSH)
  rcon_allowed_cidrs = var.restrict_ssh_to_current_ip ? [local.current_ip_cidr] : ["0.0.0.0/0"]
}
