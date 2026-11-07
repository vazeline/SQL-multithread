
-- Рекомендуется для минимизации блокировок читателей
-- ALTER DATABASE [ECommerce] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
USE [ECommerce];
GO

-- Защита от эскалации блокировок до уровня всей таблицы.
-- Без этого атомарный UPDATE в sp_ProcessSupplierBatch (пометка Status=0 -> 1 сразу по всем
-- строкам поставщика) при превышении ~5000 блокировок эскалируется в блокировку ВСЕЙ таблицы
-- Prices и начинает блокировать потоки ДРУГИХ поставщиков. DISABLE запрещает эскалацию:
-- блокировки остаются на уровне строк/ключей, и потоки разных SupplierId не мешают друг другу.
-- (TOP (4000) в циклах DELETE/UPDATE процедуры делает то же самое точечно, но атомарную
--  пометку-блокировку строк поставщика разбить на части нельзя — иначе два потока захватят
--  разные куски одного поставщика и обработают его дважды.)
ALTER TABLE dbo.Prices SET (LOCK_ESCALATION = DISABLE);
ALTER TABLE dbo.Offers  SET (LOCK_ESCALATION = DISABLE);
GO
-- Индексы под фильтрацию по SupplierId и поиск в справочниках
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Offers_SupplierId')
    CREATE NONCLUSTERED INDEX IX_Offers_SupplierId ON dbo.Offers(SupplierId);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Sku_BrandArticle')
    CREATE UNIQUE NONCLUSTERED INDEX IX_Sku_BrandArticle ON dbo.Sku(BrandId, ArticleId);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Brands_Brand')
    CREATE UNIQUE NONCLUSTERED INDEX UX_Brands_Brand ON dbo.Brands(Brand);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Articles_Article')
    CREATE UNIQUE NONCLUSTERED INDEX UX_Articles_Article ON dbo.Articles(Article);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Prices_Supplier')
    CREATE NONCLUSTERED INDEX IX_Prices_Supplier ON dbo.Prices(SupplierId, Status);
GO
