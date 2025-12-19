# Data sources for dynamic values

# Get current public IP address (the machine running Terraform)
data "http" "current_ip" {
  url = "https://api.ipify.org"

  # Only fetch if SSH restriction is enabled
  count = var.restrict_ssh_to_current_ip ? 1 : 0
}
locals {
  current_ip_cidr = var.restrict_ssh_to_current_ip ? "${trimspace(data.http.current_ip[0].response_body)}/32" : null

  # SSH allowed CIDR blocks
  ssh_allowed_cidrs = var.restrict_ssh_to_current_ip ? [local.current_ip_cidr] : ["0.0.0.0/0"]

  # RCON allowed CIDR blocks (same as SSH)
  rcon_allowed_cidrs = var.restrict_ssh_to_current_ip ? [local.current_ip_cidr] : ["0.0.0.0/0"]
}
