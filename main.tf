terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Palworld-Server"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# Generate random server password (for players to join)
resource "random_password" "server_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Avoid characters that might be confusing
  override_special = "!@#$%^&*()-_=+[]{}?"
}

# Generate random admin password (for RCON/dashboard)
resource "random_password" "admin_password" {
  length  = 20
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Avoid characters that might be confusing
  override_special = "!@#$%^&*()-_=+[]{}?"
}

# Generate SSH key pair with ED25519 (elliptic curve)
resource "tls_private_key" "palworld_ssh" {
  algorithm = "ED25519"
}

# Store the public key in AWS
resource "aws_key_pair" "palworld" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.palworld_ssh.public_key_openssh
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.palworld_ssh.private_key_openssh
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0400"
}
