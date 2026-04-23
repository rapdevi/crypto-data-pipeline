SELECT coin,
       ROUND(AVG(volume_24h_usd) / 1e9, 2) AS avg_volume_billions,
       COUNT(*) AS data_points
FROM crypto_db.processed
GROUP BY coin
ORDER BY avg_volume_billions DESC;