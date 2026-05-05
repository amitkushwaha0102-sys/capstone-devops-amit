terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "devops-accelerator-tf-state-amit2700"
    key            = "capstone/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────
# S3 — Upload Bucket
# ─────────────────────────────────────────
resource "aws_s3_bucket" "upload_bucket" {
  bucket        = var.upload_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "upload_cors" {
  bucket = aws_s3_bucket.upload_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
  }
}

# ─────────────────────────────────────────
# S3 — Frontend Bucket
# ─────────────────────────────────────────
resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = var.frontend_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend_public" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend_bucket.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend_public]
}

# ─────────────────────────────────────────
# SNS — Email Notification
# ─────────────────────────────────────────
resource "aws_sns_topic" "upload_topic" {
  name = "${var.project_name}-upload-topic"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.upload_topic.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─────────────────────────────────────────
# IAM — Lambda Role
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.upload_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.upload_topic.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda 1 — Generate Presigned URL
# ─────────────────────────────────────────
resource "aws_lambda_function" "generate_presigned_url" {
  filename         = "../../backend/generate-presigned-url/lambda.zip"
  function_name    = "${var.project_name}-generate-presigned-url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("../../backend/generate-presigned-url/lambda.zip")

  environment {
    variables = {
      BUCKET_NAME = var.upload_bucket_name
    }
  }
}

# ─────────────────────────────────────────
# Lambda 2 — Process Uploaded File
# ─────────────────────────────────────────
resource "aws_lambda_function" "process_uploaded_file" {
  filename         = "../../backend/process-uploaded-file/lambda.zip"
  function_name    = "${var.project_name}-process-uploaded-file"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("../../backend/process-uploaded-file/lambda.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.upload_topic.arn
    }
  }
}

# ─────────────────────────────────────────
# S3 Trigger — Lambda 2
# ─────────────────────────────────────────
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_uploaded_file.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn
}

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_uploaded_file.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}

# ─────────────────────────────────────────
# API Gateway
# ─────────────────────────────────────────
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.generate_presigned_url.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_url" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /get-upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}