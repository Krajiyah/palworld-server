# IAM role for EC2 instance
resource "aws_iam_role" "palworld_ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Policy for EC2 to access S3 backups
resource "aws_iam_role_policy" "palworld_s3_access" {
  name = "s3-backup-access"
  role = aws_iam_role.palworld_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}

# Policy for EC2 to attach EBS volume
resource "aws_iam_role_policy" "palworld_ebs_attach" {
  name = "ebs-volume-attach"
  role = aws_iam_role.palworld_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for EC2 to associate Elastic IP
resource "aws_iam_role_policy" "palworld_eip_associate" {
  name = "eip-associate"
  role = aws_iam_role.palworld_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AssociateAddress",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for CloudWatch metrics and logs
resource "aws_iam_role_policy" "palworld_cloudwatch" {
  name = "cloudwatch-access"
  role = aws_iam_role.palworld_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "palworld" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.palworld_ec2.name
}

# IAM role for Lambda function (volume attachment handler)
resource "aws_iam_role" "volume_attachment_lambda" {
  name = "${var.project_name}-lambda-volume-attach"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Policy for Lambda to attach EBS volume
resource "aws_iam_role_policy" "lambda_ebs_attach" {
  name = "ebs-volume-attach"
  role = aws_iam_role.volume_attachment_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for Lambda CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.volume_attachment_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
