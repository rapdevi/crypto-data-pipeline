# Crypto Data Pipeline — AWS Portfolio Project

A fully serverless, real-time data pipeline that ingests live cryptocurrency prices every 5 minutes and stores them in an S3 data lake for analysis.

## Architecture

EventBridge (every 5 min) → Lambda (ingest) → S3 raw/ → Lambda (transform) → S3 processed/ → Glue → Athena

## AWS Services Used

- **AWS Lambda** — Serverless ingestion and transformation functions
- **Amazon EventBridge** — Schedules ingestion every 5 minutes
- **Amazon S3** — Data lake storing raw JSON and processed Parquet files
- **AWS Glue** — Crawls and catalogs the Parquet data
- **Amazon Athena** — SQL queries directly on S3

## Setup Instructions

1. Create an AWS free tier account
2. Configure AWS CLI with `aws configure`
3. Create IAM role `lambda-crypto-role` with Lambda and Glue trust policy
4. Run `infrastructure/deploy.sh`
5. Add S3 trigger in Console for crypto-transform Lambda

## Data Source

CoinGecko public API — free, no API key required. Tracks BTC, ETH, and SOL.

## Sample Queries

See the `queries/` folder for Athena SQL queries.

## Free Tier

This project runs entirely within AWS free tier limits.