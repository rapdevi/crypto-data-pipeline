SELECT DATE(from_unixtime(timestamp)) AS date,
       ROUND(AVG(price_usd), 2) AS avg_price_usd,
       ROUND(MIN(price_usd), 2) AS min_price,
       ROUND(MAX(price_usd), 2) AS max_price
FROM crypto_db.processed
WHERE coin = 'bitcoin'
GROUP BY DATE(from_unixtime(timestamp))
ORDER BY date DESC;