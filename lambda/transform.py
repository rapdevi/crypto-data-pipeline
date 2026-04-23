import boto3, json, io
import pandas as pd
from datetime import datetime

s3 = boto3.client('s3')
BUCKET = 'crypto-pipeline-ralph'

def lambda_handler(event, context):
    # Get the S3 key of the file that triggered this Lambda
    record = event['Records'][0]['s3']
    key = record['object']['key']

    # Read the raw JSON from S3
    obj = s3.get_object(Bucket=BUCKET, Key=key)
    raw = json.loads(obj['Body'].read())

    # Flatten nested coin data into rows
    rows = []
    for coin, metrics in raw['data'].items():
        rows.append({
            'timestamp': raw['timestamp'],
            'coin': coin,
            'price_usd': metrics.get('usd'),
            'market_cap_usd': metrics.get('usd_market_cap'),
            'volume_24h_usd': metrics.get('usd_24h_vol'),
            'change_24h_pct': metrics.get('usd_24h_change')
        })

    df = pd.DataFrame(rows)
    df['timestamp'] = pd.to_datetime(df['timestamp'])

    # Build partitioned output path
    dt = datetime.fromisoformat(raw['timestamp'])
    out_key = (
        f"processed/year={dt.year}/month={dt.month:02d}"
        f"/day={dt.day:02d}/prices_{raw['unix_ts']}.parquet"
    )

    # Write Parquet to memory buffer and upload
    buf = io.BytesIO()
    df.to_parquet(buf, index=False, engine='pyarrow')
    buf.seek(0)
    s3.put_object(Bucket=BUCKET, Key=out_key, Body=buf.read())

    print(f"Transformed {key} → {out_key}")
    return {'statusCode': 200}