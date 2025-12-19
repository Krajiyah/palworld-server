# Package Lambda function
data "archive_file" "volume_attachment" {
  type        = "zip"
  source_file = "${path.module}/lambda/volume_attachment.py"
  output_path = "${path.module}/lambda/volume_attachment.zip"
}

# Lambda function for EBS volume attachment
resource "aws_lambda_function" "volume_attachment" {
  filename         = data.archive_file.volume_attachment.output_path
  function_name    = "${var.project_name}-volume-attachment"
  role            = aws_iam_role.volume_attachment_lambda.arn
  handler         = "volume_attachment.lambda_handler"
  source_code_hash = data.archive_file.volume_attachment.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300 # 5 minutes for volume operations

  environment {
    variables = {
      VOLUME_ID    = aws_ebs_volume.palworld_data.id
      PROJECT_NAME = var.project_name
    }
  }

  tags = {
    Name = "${var.project_name}-volume-attachment"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "volume_attachment_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.volume_attachment.function_name}"
  retention_in_days = 7
}
