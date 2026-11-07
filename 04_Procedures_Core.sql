
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
	
	-- Маркируем строки как "В обработке" в транзакции, чтобы обеспечить атомарность операции
	UPDATE dbo.Prices WITH (UPDLOCK,HOLDLOCK)
	SET Status = 1, BatchId = @BatchId
	WHERE SupplierId = @SupplierId AND Status = 0;
    	
    IF @@ROWCOUNT = 0 
	BEGIN
	  ROLLBACK TRAN;
      UPDATE dbo.PriceBatchLog
      SET Status='DONE', 
  	    RowsOffersIns = 0, 
  	    FinishedAt = SYSUTCDATETIME() 
      WHERE BatchId = @BatchId;
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
    FROM #NewOffers s;
  
    -- 2) Articles
    INSERT dbo.Articles (Article)
    SELECT DISTINCT s.Article
    FROM #NewOffers s;
  
    -- 3) Sku
    INSERT dbo.Sku (BrandId, ArticleId)
    SELECT DISTINCT b.BrandId, a.ArticleId
    FROM #NewOffers s
    JOIN dbo.Brands b ON b.Brand = s.Brand
    JOIN dbo.Articles a ON a.Article = s.Article;
  
    -- 4) Полностью заменить Offers этого SupplierId
    -- Гарантируем, что за один шаг удаляется не более 4000 строк 
	-- (это гарантированно защищает от эскалации блокировки строки до таблицы)
	WHILE 1 = 1
	BEGIN
		DELETE TOP (4000) o 
		FROM dbo.Offers o WITH (ROWLOCK)
		WHERE o.SupplierId = @SupplierId;
		
		-- Если удалять больше нечего, выходим из цикла
		IF @@ROWCOUNT = 0
			BREAK;
	END
  
    -- Таблица для маппинга ID
    CREATE TABLE #IdMapping (
        NewOfferId BIGINT,
        SourcePriceRowId UNIQUEIDENTIFIER -- ID исходной строки из таблицы Prices
    );
	
	-- 4.1) Вставка новых Offers
	-- Шаг 1. Готовим данные во временную таблицу и сразу нумеруем их по порядку (Id_Row)
	SELECT 
		ROW_NUMBER() OVER (ORDER BY s.Id) AS Id_Row,
		s.Id AS SourcePriceRowId,
		sk.SkuId, 
		s.Price,
		s.Qty
	INTO #PreparedOffers
	FROM #NewOffers s
	JOIN dbo.Brands b ON b.Brand = s.Brand
	JOIN dbo.Articles a ON a.Article = s.Article
	JOIN dbo.Sku sk ON sk.BrandId = b.BrandId AND sk.ArticleId = a.ArticleId
	ORDER BY s.Id; -- Гарантируем строгий порядок

	-- Шаг 2. Заводим таблицу для перехвата сгенерированных OfferId (тоже с автоинкрементом для связи)
	CREATE TABLE #InsertedIds (
		Id_Row INT IDENTITY(1,1),
		NewOfferId INT
	);

	-- Шаг 3. Чистый INSERT с OUTPUT. 
	-- Сортировка ORDER BY гарантирует, что порядок вставки совпадет с нумерацией Id_Row
	INSERT dbo.Offers (SupplierId, SkuId, Qty, Price)
	OUTPUT inserted.OfferId INTO #InsertedIds(NewOfferId)
	SELECT @SupplierId, SkuId, Qty, Price
	FROM #PreparedOffers
	ORDER BY Id_Row;

	-- Шаг 4. Наш готовый маппинг. Просто джойним по порядковому номеру Id_Row!
	INSERT INTO #IdMapping (NewOfferId, SourcePriceRowId)
	SELECT 
		i.NewOfferId,
		p.SourcePriceRowId
	FROM #InsertedIds i
	JOIN #PreparedOffers p ON p.Id_Row = i.Id_Row;

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
	WHILE 1 = 1
	BEGIN
		-- Обновляем только по 4000 строк за шаг, чтобы не заблокировать всю таблицу
		UPDATE TOP (4000) dbo.Prices 
		SET Status = 2 
		WHERE SupplierId = @SupplierId AND Status = 1;
		
		IF @@ROWCOUNT = 0
			BREAK;
	END
    
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
	
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
