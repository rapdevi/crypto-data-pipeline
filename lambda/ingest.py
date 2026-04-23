import json, boto3, requests, time
from datetime import datetime

s3 = boto3.client('s3')
BUCKET = 'crypto-pipeline-ralph'
COINS = ['bitcoin', 'ethereum', 'solana']

def lambda_handler(event, context):
    url = 'https://api.coingecko.com/api/v3/simple/price'
    params = {
        'ids': ','.join(COINS),
        'vs_currencies': 'usd',
        'include_market_cap': 'true',
        'include_24hr_vol': 'true',
        'include_24hr_change': 'true'
    }
    data = requests.get(url, params=params).json()
    now = datetime.utcnow()
    record = {
        'timestamp': now.isoformat(),
        'unix_ts': int(time.time()),
        'data': data
    }
    key = (f"raw/year={now.year}/month={now.month:02d}"
           f"/day={now.day:02d}/prices_{record['unix_ts']}.json")
    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=json.dumps(record)
    )
    return {'statusCode': 200, 'body': 'Ingested successfully'}