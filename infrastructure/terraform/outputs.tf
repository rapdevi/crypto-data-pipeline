output "s3_bucket_name" {
  description = "Main S3 bucket name"
  value       = aws_s3_bucket.crypto_pipeline.bucket
}

output "athena_bucket_name" {
  description = "Athena results bucket name"
  value       = aws_s3_bucket.athena_results.bucket
}

output "ingest_lambda_arn" {
  description = "Ingest Lambda ARN"
  value       = aws_lambda_function.crypto_ingest.arn
}

output "transform_lambda_arn" {
  description = "Transform Lambda ARN"
  value       = aws_lambda_function.crypto_transform.arn
}

output "sns_topic_arn" {
  description = "SNS alerts topic ARN"
  value       = aws_sns_topic.crypto_alerts.arn
}

output "glue_database" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.crypto_db.name
}
