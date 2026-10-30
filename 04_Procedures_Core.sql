
CREATE OR ALTER PROCEDURE dbo.sp_ProcessSupplierBatch(
	@SupplierId INT
)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

  IF NOT EXISTS(SELECT 1 FROM dbo.Suppliers WHERE SupplierId = @SupplierId) 
  BEGIN
    INSERT dbo.PriceProcessErrorLog(BatchId,SupplierId,ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage)
    VALUES (@BatchId,@SupplierId,NULL,NULL,NULL,NULL,NULL,'Supplier with SupplierId=' + @SupplierId +' not found');
    
	RETURN;
  END

  INSERT INTO dbo.PriceBatchLog (BatchId, SupplierId, Status, RowsIn, StartedAt)
  SELECT @BatchId, @SupplierId, 'ENQUEUED', COUNT(*), SYSUTCDATETIME()
  FROM dbo.Prices WHERE SupplierId = @SupplierId;
 
  
  BEGIN TRY
  
    BEGIN TRAN;
    -- Маркируем строки как "В обработке"
    UPDATE dbo.Prices WITH (UPDLOCK,HOLDLOCK)
    SET Status = 1, BatchId = @BatchId
    WHERE SupplierId = @SupplierId AND Status = 0;
    	
    IF @@ROWCOUNT = 0 
	BEGIN
	  ROLLBACK TRAN
	  RETURN;
	END
	
    COMMIT;
	
    CREATE TABLE #NewOffers(Brand VARCHAR(100), Article VARCHAR(100), Price MONEY, Qty INT, Descr VARCHAR(255), Id UNIQUEIDENTIFIER);
    
    -- 1. Сначала готовим данные в памяти/tempdb БЕЗ транзакции и блокировок основной таблицы
    INSERT INTO #NewOffers(Brand, Article, Price, Qty, Descr, Id )
    SELECT LTRIM(RTRIM(Brand)) Brand, LTRIM(RTRIM(Article)) Article, p.Price, p.Qty, p.Descr, NEWID() Id
    FROM dbo.Prices p
    WHERE p.SupplierId = @SupplierId AND p.Status = 1; 
 
    UPDATE dbo.PriceBatchLog 
    SET Status='PROCESSING', 
  	  StartedAt = ISNULL(StartedAt, SYSUTCDATETIME()) 
    WHERE BatchId = @BatchId;
  
    -- 1) Brands
    INSERT dbo.Brands (Brand)
    SELECT DISTINCT s.Brand
    FROM #NewOffers s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Brands b WITH (UPDLOCK,HOLDLOCK) WHERE b.Brand = s.Brand);
  
    -- 2) Articles
    INSERT dbo.Articles (Article)
    SELECT DISTINCT s.Article
    FROM #NewOffers s
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Articles a WITH (UPDLOCK,HOLDLOCK) WHERE a.Article = s.Article);
  
    -- 3) Sku
    INSERT dbo.Sku (BrandId, ArticleId)
    SELECT DISTINCT b.BrandId, a.ArticleId
    FROM #NewOffers s
    JOIN dbo.Brands b ON b.Brand = s.Brand
    JOIN dbo.Articles a ON a.Article = s.Article
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Sku sk WITH (UPDLOCK,HOLDLOCK) WHERE sk.BrandId = b.BrandId AND sk.ArticleId = a.ArticleId);
  
    -- 4) Полностью заменить Offers этого SupplierId
    DELETE o FROM dbo.Offers o WITH (ROWLOCK) WHERE o.SupplierId = @SupplierId;
  
    -- Таблица для маппинга ID
    CREATE TABLE #IdMapping (
        NewOfferId BIGINT,
        SourcePriceRowId UNIQUEIDENTIFIER -- ID исходной строки из таблицы Prices
    );
    
    INSERT INTO dbo.Offers(SupplierId, SkuId, Qty, Price) 
	OUTPUT inserted.OfferId, source.Id -- Связываем созданный ID с исходным ID строки
    INTO #IdMapping (NewOfferId, SourcePriceRowId)
    SELECT @SupplierId, s.SkuId, s.Qty, s.Price
	FROM #NewOffers s
	JOIN dbo.Brands b ON b.Brand = s.Brand
	JOIN dbo.Articles a ON a.Article = s.Article
	JOIN dbo.Sku sk ON sk.BrandID = b.BrandID AND sk.ArticleID = a.ArticleID
;

    -- 5) Descr по новым OfferId
    INSERT dbo.Descr (OfferId, Descr)
    SELECT m.NewOfferId, s.Descr
    FROM #IdMapping m 
	JOIN #NewOffers s ON s.Id = m.SourcePriceRowId
	WHERE s.Descr IS NOT NULL;
  
    UPDATE dbo.PriceBatchLog 
    SET Status='DONE', 
  	  RowsOffersIns = (SELECT COUNT(*) FROM dbo.Offers WHERE SupplierId = @SupplierId), 
  	  FinishedAt = SYSUTCDATETIME() 
    WHERE BatchId = @BatchId;
    
    -- Финализируем статус во входной таблице
    UPDATE dbo.Prices 
    SET Status = 2 
    WHERE SupplierId = @SupplierId AND Status = 1;
    
  END TRY
  BEGIN CATCH
    
    INSERT dbo.PriceProcessErrorLog(BatchId,SupplierId,ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage)
    VALUES (@BatchId,@SupplierId,ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(),ERROR_PROCEDURE(),ERROR_LINE(),ERROR_MESSAGE());
    
    UPDATE dbo.PriceBatchLog 
    SET Status='ERROR', 
  	  ErrMsg = ERROR_MESSAGE(), 
  	  FinishedAt = SYSUTCDATETIME() 
    WHERE BatchId = @BatchId;
    
    -- Помечаем строки ошибкой
    UPDATE dbo.Prices 
    SET Status = 3
    WHERE SupplierId = @SupplierId AND Status = 1;
  	
  END CATCH
  
END
GO
