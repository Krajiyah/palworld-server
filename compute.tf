# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch template for Palworld server
resource "aws_launch_template" "palworld" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.palworld.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.palworld.arn
  }

  vpc_security_group_ids = [aws_security_group.palworld.id]

  # Spot instance configuration
  instance_market_options {
    market_type = "spot"

    spot_options {
      max_price          = var.spot_price_max
      spot_instance_type = "one-time"  # ASG requires one-time Spot instances
      instance_interruption_behavior = "terminate"
    }
  }

  # Block device mapping for root volume
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # User data script - gzip compressed to fit within 16KB limit
  user_data = base64gzip(templatefile("${path.module}/user-data.sh", {
    region                  = var.aws_region
    project_name            = var.project_name
    eip_allocation_id       = aws_eip.palworld.id
    data_volume_id          = aws_ebs_volume.palworld_data.id
    s3_bucket               = aws_s3_bucket.backups.id
    server_name             = var.palworld_server_name
    server_password         = random_password.server_password.result
    admin_password          = random_password.admin_password.result
    max_players             = var.palworld_max_players
    backup_cron_schedule    = var.backup_cron_schedule
    enable_dashboard        = var.enable_dashboard
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 for security
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for automatic recovery
resource "aws_autoscaling_group" "palworld" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = [aws_subnet.public.id] # Single AZ for EBS volume
  desired_capacity    = 1
  min_size            = 0  # Set to 0 to allow full teardown
  max_size            = 1
  health_check_type   = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.palworld.id
    version = "$Latest"
  }

  # Lifecycle hook for EBS volume attachment
  initial_lifecycle_hook {
    name                 = "attach-ebs-volume"
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# SNS topic for ASG lifecycle hooks
resource "aws_sns_topic" "asg_lifecycle" {
  name = "${var.project_name}-asg-lifecycle"
}

# SNS topic subscription for Lambda
resource "aws_sns_topic_subscription" "asg_lifecycle_lambda" {
  topic_arn = aws_sns_topic.asg_lifecycle.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.volume_attachment.arn
}

# Lambda permission to be invoked by SNS
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.volume_attachment.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.asg_lifecycle.arn
}

# Update ASG to send lifecycle notifications to SNS
resource "aws_autoscaling_lifecycle_hook" "attach_volume" {
  name                   = "attach-ebs-volume"
  autoscaling_group_name = aws_autoscaling_group.palworld.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  notification_target_arn = aws_sns_topic.asg_lifecycle.arn
  role_arn               = aws_iam_role.asg_lifecycle.arn
}

# IAM role for ASG lifecycle hook
resource "aws_iam_role" "asg_lifecycle" {
  name = "${var.project_name}-asg-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "autoscaling.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for ASG to publish to SNS
resource "aws_iam_role_policy" "asg_lifecycle_sns" {
  name = "sns-publish"
  role = aws_iam_role.asg_lifecycle.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.asg_lifecycle.arn
      }
    ]
  })
}
