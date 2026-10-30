USE [ECommerce];
GO

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- =====================================================
-- ТЕСТ 1: Последовательно - разные поставщики
-- =====================================================
PRINT '=== TEST 1: SEQUENTIAL SupplierId=1 THEN SupplierId=2 ===';
DECLARE @t1a DATETIME2 = SYSUTCDATETIME();
EXEC dbo.sp_ProcessSupplierBatch @SupplierId = 1;
DECLARE @t1b DATETIME2 = SYSUTCDATETIME();
EXEC dbo.sp_ProcessSupplierBatch @SupplierId = 2;
DECLARE @t1c DATETIME2 = SYSUTCDATETIME();
PRINT 'Duration 1: ' + CAST(DATEDIFF(MILLISECOND,@t1a,@t1b) AS VARCHAR(10)) + ' ms';
PRINT 'Duration 2: ' + CAST(DATEDIFF(MILLISECOND,@t1b,@t1c) AS VARCHAR(10)) + ' ms';
PRINT 'Total:      ' + CAST(DATEDIFF(MILLISECOND,@t1a,@t1c) AS VARCHAR(10)) + ' ms';

-- =====================================================
-- ТЕСТ 2: Параллельно - РАЗНЫЕ поставщики
-- ВЫПОЛНИТЬ В ДРУГОМ ОКНЕ SSMS ОДНОВРЕМЕННО:
--   EXEC dbo.sp_ProcessSupplierBatch @SupplierId = 2;
-- (пока в этом окне крутится ТЕСТ 1 или запустить оба окна одновременно)
-- =====================================================

-- =====================================================
-- ТЕСТ 3: Параллельно - ОДИН И ТОТ ЖЕ поставщик
-- Сбросить перед тестом:
--   UPDATE dbo.Prices SET Status=0 WHERE SupplierId=1;
--   TRUNCATE TABLE dbo.Descr; DELETE FROM dbo.Offers;
--   DELETE FROM dbo.PriceBatchLog; DELETE FROM dbo.PriceProcessErrorLog;
--
-- Затем ОДНОВРЕМЕННО в ДВУХ окнах SSMS выполнить:
--   EXEC dbo.sp_ProcessSupplierBatch @SupplierId = 1;  (окно A)
--   EXEC dbo.sp_ProcessSupplierBatch @SupplierId = 1;  (окно B)
--
-- Итог: должен отработать ТОЛЬКО один. Второй либо дождётся блокировки и обработает 0 строк,
-- либо (если добавить sp_getapplock) сразу завершится с сообщением о невозможности захватить блокировку
-- =====================================================

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Мониторинг
-- SELECT * FROM dbo.PriceBatchLog ORDER BY StartedAt DESC;
-- SELECT * FROM dbo.PriceProcessErrorLog ORDER BY LogAt DESC;
GO