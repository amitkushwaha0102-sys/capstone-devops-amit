output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = "${aws_apigatewayv2_api.api.api_endpoint}/get-upload-url"
}

output "frontend_bucket_name" {
  description = "Frontend S3 bucket name"
  value       = aws_s3_bucket.frontend_bucket.bucket
}

output "upload_bucket_name" {
  description = "Upload S3 bucket name"
  value       = aws_s3_bucket.upload_bucket.bucket
}

output "cloudfront_url" {
  description = "Frontend website URL"
  value       = aws_s3_bucket_website_configuration.frontend_website.website_endpoint
}