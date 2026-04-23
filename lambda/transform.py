import boto3, json, io
import pandas as pd
from datetime import datetime, timezone, timedelta
from urllib.parse import unquote_plus

s3 = boto3.client('s3')
sns = boto3.client('sns')

BUCKET = 'crypto-pipeline-ralph'
SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:722851018793:crypto-price-alerts'
# DROP_THRESHOLD = -10.0
DROP_THRESHOLD = -10.0

def get_price_one_hour_ago(coin, current_time):
    one_hour_ago = current_time - timedelta(hours=1)
    prefix = (
        f"processed/year={one_hour_ago.year}"
        f"/month={one_hour_ago.month:02d}"
        f"/day={one_hour_ago.day:02d}/"
    )
    try:
        response = s3.list_objects_v2(Bucket=BUCKET, Prefix=prefix)
        if 'Contents' not in response:
            return None
        files = sorted(response['Contents'], key=lambda x: x['LastModified'])
        if not files:
            return None
        obj = s3.get_object(Bucket=BUCKET, Key=files[-1]['Key'])
        df_old = pd.read_parquet(io.BytesIO(obj['Body'].read()))
        row = df_old[df_old['coin'] == coin]
        if row.empty:
            return None
        return float(row['price_usd'].iloc[0])
    except Exception as e:
        print(f"Could not fetch historical price for {coin}: {e}")
        return None


def check_anomalies(df, current_time):
    alerts = []
    for _, row in df.iterrows():
        coin = row['coin']
        current_price = row['price_usd']
        old_price = get_price_one_hour_ago(coin, current_time)
        if old_price is None or old_price == 0:
            print(f"No historical data found for {coin}, skipping.")
            continue
        pct_change = ((current_price - old_price) / old_price) * 100
        print(f"{coin}: old={old_price}, current={current_price}, change={pct_change:.2f}%")
        if pct_change <= DROP_THRESHOLD:
            alerts.append({
                'coin': coin,
                'old_price': round(old_price, 2),
                'current_price': round(current_price, 2),
                'pct_change': round(pct_change, 2)
            })
    return alerts


def send_alert(alerts, current_time):
    lines = []
    for alert in alerts:
        lines.append(
            f"- {alert['coin'].upper()}: dropped {alert['pct_change']}% in the last hour\n"
            f"  1 hour ago: ${alert['old_price']:,}\n"
            f"  Current:    ${alert['current_price']:,}"
        )
    message = (
        f"CRYPTO PRICE ALERT — {current_time.strftime('%Y-%m-%d %H:%M UTC')}\n"
        f"{'=' * 50}\n\n"
        f"The following coins dropped more than {abs(DROP_THRESHOLD)}% in the last hour:\n\n"
        + "\n\n".join(lines) +
        f"\n\n{'=' * 50}\n"
        f"Powered by your AWS crypto pipeline."
    )
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"Crypto Alert: Price Drop Detected ({len(alerts)} coin(s))",
        Message=message
    )
    print(f"Alert sent for: {[a['coin'] for a in alerts]}")


def lambda_handler(event, context):
    try:
        record = event['Records'][0]['s3']
        key = unquote_plus(record['object']['key'])
    except (KeyError, IndexError) as e:
        print(f"Invalid event structure: {e}")
        print(f"Event received: {json.dumps(event)}")
        return {'statusCode': 400, 'body': 'Invalid event structure'}

    print(f"Processing key: {key}")

    obj = s3.get_object(Bucket=BUCKET, Key=key)
    raw = json.loads(obj['Body'].read())

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
    current_time = datetime.now(timezone.utc)

    dt = datetime.fromisoformat(raw['timestamp'])
    out_key = (
        f"processed/year={dt.year}/month={dt.month:02d}"
        f"/day={dt.day:02d}/prices_{raw['unix_ts']}.parquet"
    )
    buf = io.BytesIO()
    df.to_parquet(buf, index=False, engine='pyarrow')
    buf.seek(0)
    s3.put_object(Bucket=BUCKET, Key=out_key, Body=buf.read())
    print(f"Saved: {out_key}")

    alerts = check_anomalies(df, current_time)
    if alerts:
        send_alert(alerts, current_time)
    else:
        print("No anomalies detected.")

    return {
        'statusCode': 200,
        'body': f"Processed {len(rows)} coins, {len(alerts)} alerts triggered."
    }