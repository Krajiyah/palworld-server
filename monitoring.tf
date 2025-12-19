# CloudWatch Log Group for server logs
resource "aws_cloudwatch_log_group" "palworld_server" {
  name              = "/palworld/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# CloudWatch alarm for high CPU
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 CPU utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.palworld.name
  }
}

# CloudWatch alarm for high memory (requires CloudWatch agent)
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.project_name}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors memory utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.palworld.name
  }
}

# EventBridge rule for EC2 Spot Instance interruption warnings
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.project_name}-spot-interruption"
  description = "Capture EC2 Spot Instance interruption warnings"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

# Lambda function for spot interruption handling (backup before termination)
resource "aws_lambda_function" "spot_interruption_handler" {
  filename         = data.archive_file.spot_interruption_handler.output_path
  function_name    = "${var.project_name}-spot-interruption"
  role            = aws_iam_role.spot_interruption_lambda.arn
  handler         = "spot_interruption.lambda_handler"
  source_code_hash = data.archive_file.spot_interruption_handler.output_base64sha256
  runtime         = "python3.11"
  timeout         = 120 # 2 minutes to match Spot warning time

  environment {
    variables = {
      S3_BUCKET    = aws_s3_bucket.backups.id
      PROJECT_NAME = var.project_name
    }
  }

  tags = {
    Name = "${var.project_name}-spot-interruption"
  }
}

# Package spot interruption Lambda
data "archive_file" "spot_interruption_handler" {
  type        = "zip"
  source_file = "${path.module}/lambda/spot_interruption.py"
  output_path = "${path.module}/lambda/spot_interruption.zip"
}

# IAM role for spot interruption Lambda
resource "aws_iam_role" "spot_interruption_lambda" {
  name = "${var.project_name}-lambda-spot-interruption"

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

# Policy for spot interruption Lambda
resource "aws_iam_role_policy" "spot_interruption_lambda" {
  name = "spot-interruption-handler"
  role = aws_iam_role.spot_interruption_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "spot_interruption_lambda_logs" {
  role       = aws_iam_role.spot_interruption_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# EventBridge target for spot interruption
resource "aws_cloudwatch_event_target" "spot_interruption_lambda" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "SpotInterruptionLambda"
  arn       = aws_lambda_function.spot_interruption_handler.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke_spot" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.spot_interruption_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.spot_interruption.arn
}

# CloudWatch Log Group for spot interruption Lambda
resource "aws_cloudwatch_log_group" "spot_interruption_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.spot_interruption_handler.function_name}"
  retention_in_days = 7
}
