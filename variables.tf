variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "palworld-server"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "EC2 instance type (must have 16GB+ RAM)"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16GB RAM
}

variable "spot_price_max" {
  description = "Maximum Spot price per hour (empty for on-demand price)"
  type        = string
  default     = "0.10" # ~60% discount from on-demand
}

variable "palworld_server_name" {
  description = "Name of your Palworld server"
  type        = string
  default     = "My Palworld Server"
}

# Passwords are automatically generated using random_password resources
# See main.tf for password generation configuration
# Retrieve passwords using: terraform output server_password

variable "palworld_max_players" {
  description = "Maximum number of players (16GB RAM supports ~10-20)"
  type        = number
  default     = 16

  validation {
    condition     = var.palworld_max_players >= 4 && var.palworld_max_players <= 32
    error_message = "Max players must be between 4 and 32"
  }
}

variable "backup_cron_schedule" {
  description = "Cron schedule for S3 backups (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"
}

variable "restrict_ssh_to_current_ip" {
  description = "Restrict SSH access to the IP address of the machine running Terraform (automatically detected)"
  type        = bool
  default     = false
}

variable "enable_dashboard" {
  description = "Enable web monitoring dashboard on port 80"
  type        = bool
  default     = true
}

variable "ami_id" {
  description = "AMI ID for Ubuntu 22.04 LTS (leave empty for automatic lookup)"
  type        = string
  default     = ""
}

variable "palworld_base_camp_max_num_in_guild" {
  description = "Maximum number of bases per guild (default: 4, max: 10)"
  type        = number
  default     = 10

  validation {
    condition     = var.palworld_base_camp_max_num_in_guild >= 1 && var.palworld_base_camp_max_num_in_guild <= 10
    error_message = "Base camp max num in guild must be between 1 and 10"
  }
}

variable "palworld_base_camp_worker_max_num" {
  description = "Maximum number of Pals working at each base (default: 15, max: 30)"
  type        = number
  default     = 22

  validation {
    condition     = var.palworld_base_camp_worker_max_num >= 1 && var.palworld_base_camp_worker_max_num <= 30
    error_message = "Base camp worker max num must be between 1 and 30"
  }
}

variable "palworld_force_update" {
  description = "Change this value to trigger a server update (pulls latest Docker image). Increment to force update, e.g., v1 -> v2"
  type        = string
  default     = "v1"
}
