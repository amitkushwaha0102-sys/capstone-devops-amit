variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "upload_bucket_name" {
  description = "S3 bucket for file uploads"
  type        = string
}

variable "frontend_bucket_name" {
  description = "S3 bucket for frontend hosting"
  type        = string
}

variable "alert_email" {
  description = "Email for SNS notifications"
  type        = string
}