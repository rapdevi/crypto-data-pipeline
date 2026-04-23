
#!/bin/bash
# Full deployment script for crypto-data-pipeline

BUCKET_NAME="crypto-pipeline-ralph"
ACCOUNT_ID="722851018793"
REGION="us-east-1"

echo "Step 1: Creating S3 buckets..."
aws s3 mb s3://$BUCKET_NAME --region $REGION
aws s3 mb s3://crypto-athena-results-ralph --region $REGION

echo "Step 2: Packaging ingest Lambda..."
mkdir -p package
pip install requests -t package/
cp lambda/ingest.py package/
cd package && zip -r ../ingest.zip . && cd ..

echo "Step 3: Deploying ingest Lambda..."
aws lambda create-function \
  --function-name crypto-ingest \
  --runtime python3.11 \
  --handler ingest.lambda_handler \
  --zip-file fileb://ingest.zip \
  --role arn:aws:iam::$ACCOUNT_ID:role/lambda-crypto-role \
  --timeout 30 \
  --memory-size 128

echo "Step 4: Scheduling ingest every 5 minutes via EventBridge..."
aws events put-rule \
  --name crypto-every-5-min \
  --schedule-expression "rate(5 minutes)" \
  --state ENABLED

aws events put-targets \
  --rule crypto-every-5-min \
  --targets "Id=1,Arn=arn:aws:lambda:$REGION:$ACCOUNT_ID:function:crypto-ingest"

aws lambda add-permission \
  --function-name crypto-ingest \
  --statement-id allow-eventbridge \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:$REGION:$ACCOUNT_ID:rule/crypto-every-5-min

echo "Step 5: Packaging transform Lambda..."
mkdir -p package2
cp lambda/transform.py package2/
cd package2 && zip -r ../transform.zip . && cd ..

echo "Step 6: Deploying transform Lambda..."
aws lambda create-function \
  --function-name crypto-transform \
  --runtime python3.11 \
  --handler transform.lambda_handler \
  --zip-file fileb://transform.zip \
  --role arn:aws:iam::$ACCOUNT_ID:role/lambda-crypto-role \
  --timeout 60 \
  --memory-size 256 \
  --layers arn:aws:lambda:$REGION:336392948345:layer:AWSSDKPandas-Python311:17

echo "Step 7: Adding S3 trigger permission for transform Lambda..."
aws lambda add-permission \
  --function-name crypto-transform \
  --statement-id allow-s3-trigger \
  --action lambda:InvokeFunction \
  --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::$BUCKET_NAME \
  --source-account $ACCOUNT_ID

echo "Step 8: Setting up Glue catalog..."
aws glue create-database \
  --database-input '{"Name":"crypto_db"}'

aws glue create-crawler \
  --name crypto-crawler \
  --role arn:aws:iam::$ACCOUNT_ID:role/lambda-crypto-role \
  --database-name crypto_db \
  --targets "{\"S3Targets\":[{\"Path\":\"s3://$BUCKET_NAME/processed/\"}]}"

echo "============================================"
echo "Deployment complete!"
echo "MANUAL STEP REQUIRED:"
echo "Go to AWS Console -> Lambda -> crypto-transform"
echo "-> Add trigger -> S3 -> Bucket: $BUCKET_NAME"
echo "-> Prefix: raw/ -> Suffix: .json -> Save"
echo "============================================"