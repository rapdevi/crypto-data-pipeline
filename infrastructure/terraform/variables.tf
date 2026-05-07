variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "722851018793"
}

variable "bucket_name" {
  description = "Main S3 bucket for crypto pipeline"
  type        = string
  default     = "crypto-pipeline-ralph"
}

variable "athena_bucket_name" {
  description = "S3 bucket for Athena query results"
  type        = string
  default     = "crypto-athena-results-ralph"
}

variable "alert_email" {
  description = "Email address for SNS price alerts"
  type        = string
  default     = "ralphdelavictoria@gmail.com"
}

variable "drop_threshold" {
  description = "Price drop percentage to trigger alert"
  type        = number
  default     = 5.0
}
