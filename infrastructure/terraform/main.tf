# ── S3 Buckets ──────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "crypto_pipeline" {
  bucket = var.bucket_name

  tags = {
    Project     = "crypto-data-pipeline"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket = var.athena_bucket_name

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

# ── IAM Role ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_crypto_role" {
  name = "lambda-crypto-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "glue.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_glue" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "lambda_athena" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_sns" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

# ── SNS Topic & Subscription ─────────────────────────────────────────────────

resource "aws_sns_topic" "crypto_alerts" {
  name = "crypto-price-alerts"

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.crypto_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Lambda Functions ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "crypto_ingest" {
  function_name = "crypto-ingest"
  role          = aws_iam_role.lambda_crypto_role.arn
  handler       = "ingest.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 128
  filename      = "${path.module}/../../lambda/ingest.zip"

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

resource "aws_lambda_function" "crypto_transform" {
  function_name = "crypto-transform"
  role          = aws_iam_role.lambda_crypto_role.arn
  handler       = "transform.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256
  filename      = "${path.module}/../../lambda/transform.zip"

  layers = [
    "arn:aws:lambda:${var.aws_region}:336392948345:layer:AWSSDKPandas-Python311:17"
  ]

  environment {
    variables = {
      BUCKET_NAME    = var.bucket_name
      SNS_TOPIC_ARN  = aws_sns_topic.crypto_alerts.arn
      DROP_THRESHOLD = tostring(var.drop_threshold)
    }
  }

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

# ── Lambda Concurrency Limits ─────────────────────────────────────────────────

resource "aws_lambda_function_event_invoke_config" "ingest_config" {
  function_name = aws_lambda_function.crypto_ingest.function_name
  maximum_retry_attempts = 0
}

# ── EventBridge Schedule ──────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "every_5_min" {
  name                = "crypto-every-5-min"
  description         = "Triggers crypto ingest Lambda every 5 minutes"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

resource "aws_cloudwatch_event_target" "ingest_target" {
  rule      = aws_cloudwatch_event_rule.every_5_min.name
  target_id = "CryptoIngestLambda"
  arn       = aws_lambda_function.crypto_ingest.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "allow-eventbridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crypto_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_5_min.arn
}

# ── S3 Trigger for Transform Lambda ──────────────────────────────────────────

resource "aws_lambda_permission" "allow_s3_trigger" {
  statement_id  = "allow-s3-trigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crypto_transform.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.crypto_pipeline.arn
  source_account = var.account_id
}

resource "aws_s3_bucket_notification" "raw_trigger" {
  bucket = aws_s3_bucket.crypto_pipeline.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.crypto_transform.arn
    events              = ["s3:ObjectCreated:Put"]
    filter_prefix       = "raw/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_trigger]
}

# ── Glue Database & Crawler ───────────────────────────────────────────────────

resource "aws_glue_catalog_database" "crypto_db" {
  name = "crypto_db"
}

resource "aws_glue_crawler" "crypto_crawler" {
  name          = "crypto-crawler"
  role          = aws_iam_role.lambda_crypto_role.arn
  database_name = aws_glue_catalog_database.crypto_db.name

  s3_target {
    path = "s3://${var.bucket_name}/processed/"
  }

  tags = {
    Project   = "crypto-data-pipeline"
    ManagedBy = "terraform"
  }
}

# ── S3 Lifecycle Policy ───────────────────────────────────────────────────────

resource "aws_s3_bucket_lifecycle_configuration" "raw_retention" {
  bucket = aws_s3_bucket.crypto_pipeline.id

  rule {
    id     = "delete-raw-after-90-days"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = 90
    }
  }
}

# ── Billing Alarm ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "billing_alert" {
  alarm_name          = "billing-alert-1-dollar"
  alarm_description   = "Alert if AWS bill exceeds $1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  statistic           = "Maximum"
  period              = 86400
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  alarm_actions       = [aws_sns_topic.crypto_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_glue_console" {
  role       = aws_iam_role.lambda_crypto_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}
