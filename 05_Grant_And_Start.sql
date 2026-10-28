-- 05_Grant_And_Start.sql
-- Запуск обработки
EXEC dbo.sp_EnqueuePriceBatches;

-- Мониторинг
-- SELECT * FROM dbo.PriceBatchLog ORDER BY StartedAt DESC;
-- SELECT * FROM dbo.PriceBatchQueue WITH(NOLOCK);
-- SELECT * FROM dbo.PriceProcessErrorLog ORDER BY LogAt DESC;
GO
