# Persistent EBS volume for game data
resource "aws_ebs_volume" "palworld_data" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 50 # GB - enough for game files and saves
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-data-volume"
    Persistent  = "true"
    AutoAttach  = "true"
    MountPoint  = "/mnt/palworld-data"
  }

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false # Set to true after first apply for safety
  }
}

# S3 bucket for backups (disaster recovery)
resource "aws_s3_bucket" "backups" {
  bucket_prefix = "${var.project_name}-backups-"
  force_destroy = true # Allows terraform destroy to work

  tags = {
    Name = "${var.project_name}-backups"
  }
}

# Enable versioning for backup protection
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy to reduce costs
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "cleanup-old-backups"
    status = "Enabled"

    filter {}

    # Keep daily backups for 7 days
    expiration {
      days = 7
    }

    # Delete old versions after 14 days (no transition needed for short retention)
    noncurrent_version_expiration {
      noncurrent_days = 14
    }
  }
}

# Block public access to backup bucket
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Elastic IP for static address
resource "aws_eip" "palworld" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }

  # EIP depends on IGW
  depends_on = [aws_internet_gateway.palworld]
}
