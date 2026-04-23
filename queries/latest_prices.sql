SELECT coin, price_usd, change_24h_pct, timestamp
FROM crypto_db.processed
ORDER BY timestamp DESC
LIMIT 10;