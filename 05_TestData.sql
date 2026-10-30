USE [ECommerce];
GO

-- Очистка под повторный прогон
DELETE FROM dbo.Prices;
TRUNCATE TABLE dbo.Descr;
DELETE FROM dbo.Offers;
DELETE FROM dbo.Sku;
DELETE FROM dbo.Articles;
DELETE FROM dbo.Brands;
DELETE FROM dbo.PriceBatchLog;
DELETE FROM dbo.PriceProcessErrorLog;

-- Поставщики
IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE SupplierId=1) INSERT dbo.Suppliers(SupplierId,SupplierName) VALUES(1,'Supplier1');
IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers WHERE SupplierId=2) INSERT dbo.Suppliers(SupplierId,SupplierName) VALUES(2,'Supplier2');

-- Прайс для SupplierId=1 (5000 строк)
DECLARE @i INT = 1;
WHILE @i <= 5000
BEGIN
  INSERT dbo.Prices (SupplierId, Brand, Article, Qty, Price, Descr, Status, BatchId)
  VALUES (
    1,
    'BRAND' + CAST((@i % 40) + 1 AS VARCHAR(10)),
    'ART'   + RIGHT('000000' + CAST(@i AS VARCHAR(6)), 6),
    (@i % 50) + 1,
    CAST((RAND(CHECKSUM(NEWID())) * 1000 + 10) AS MONEY),
    CASE WHEN (@i % 3) = 0 THEN 'Descr ' + CAST(@i AS VARCHAR(10)) ELSE NULL END,
    0,
    NEWID()
  );
  SET @i += 1;
END

-- Прайс для SupplierId=2 (5000 строк) с пересечением по брендам/артикулам
SET @i = 1;
WHILE @i <= 5000
BEGIN
  INSERT dbo.Prices (SupplierId, Brand, Article, Qty, Price, Descr, Status, BatchId)
  VALUES (
    2,
    'BRAND' + CAST((@i % 40) + 1 AS VARCHAR(10)),  -- пересекаются
    'ART2'  + RIGHT('000000' + CAST((@i % 2500) + 1 AS VARCHAR(6)), 6), -- часть пересекается
    (@i % 30) + 1,
    CAST((RAND(CHECKSUM(NEWID())) * 1500 + 5) AS MONEY),
    'Desc2 ' + CAST(@i AS VARCHAR(10)),
    0,
    NEWID()
  );
  SET @i += 1;
END

SELECT SupplierId, COUNT(*) AS Cnt, SUM(CASE WHEN Status=0 THEN 1 ELSE 0 END) AS Cnt0
FROM dbo.Prices
GROUP BY SupplierId;
GO