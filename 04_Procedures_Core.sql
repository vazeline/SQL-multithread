-- 04_Procedures_Core.sql
CREATE OR ALTER PROCEDURE dbo.sp_EnqueuePriceBatches
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    DECLARE @SupplierId INT, @BatchId UNIQUEIDENTIFIER, @DlgHandle UNIQUEIDENTIFIER;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
      SELECT DISTINCT SupplierId FROM dbo.Prices;

    OPEN cur;
    FETCH NEXT FROM cur INTO @SupplierId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @BatchId = NEWID();
      INSERT INTO dbo.PriceBatchLog (BatchId, SupplierId, Status, RowsIn, StartedAt)
      SELECT @BatchId, @SupplierId, 'ENQUEUED', COUNT(*), SYSUTCDATETIME()
      FROM dbo.Prices WHERE SupplierId = @SupplierId;

      INSERT INTO dbo.PriceBatchStaging (BatchId, SupplierId, Brand, Article, Qty, Price, Descr)
      SELECT @BatchId, @SupplierId, LTRIM(RTRIM(Brand)), LTRIM(RTRIM(Article)), Qty, Price, Descr
      FROM dbo.Prices WHERE SupplierId = @SupplierId;

      BEGIN DIALOG @DlgHandle
        FROM SERVICE [http://ecommerce/prices/PriceBatchService]
        TO SERVICE 'http://ecommerce/prices/PriceBatchService'
        ON CONTRACT [http://ecommerce/prices/PriceBatchContract]
        WITH ENCRYPTION = OFF;

      SEND ON CONVERSATION @DlgHandle
        MESSAGE TYPE [http://ecommerce/prices/PriceBatch]
        (@BatchId);

      END CONVERSATION @DlgHandle;

      FETCH NEXT FROM cur INTO @SupplierId;
    END
    CLOSE cur;
    DEALLOCATE cur;
  END TRY
  BEGIN CATCH
    IF CURSOR_STATUS('local','cur') >= -1 BEGIN CLOSE cur; DEALLOCATE cur; END
    INSERT dbo.PriceProcessErrorLog(ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage)
    VALUES (ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(),ERROR_PROCEDURE(),ERROR_LINE(),ERROR_MESSAGE());
    THROW;
  END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_ProcessSupplierBatch
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @DlgHandle UNIQUEIDENTIFIER, @MsgType SYSNAME, @MsgBody XML;
  WHILE 1=1
  BEGIN
    WAITFOR (
      RECEIVE TOP (1)
        @DlgHandle = conversation_handle,
        @MsgType   = message_type_name,
        @MsgBody   = CAST(message_body AS XML)
      FROM dbo.PriceBatchQueue
    ), TIMEOUT 1000;

    IF @@ROWCOUNT = 0 BREAK;
    IF @MsgType = 'http://schemas.microsoft.com/SQL/ServiceBroker/EndDialog'
    BEGIN
      END CONVERSATION @DlgHandle;
      CONTINUE;
    END
    IF @MsgType = 'http://schemas.microsoft.com/SQL/ServiceBroker/Error'
    BEGIN
      END CONVERSATION @DlgHandle;
      CONTINUE;
    END

    DECLARE @BatchId UNIQUEIDENTIFIER = TRY_CAST(@MsgBody.value('(/BatchId)[1]','uniqueidentifier') AS UNIQUEIDENTIFIER);
    IF @BatchId IS NULL CONTINUE;

    BEGIN TRY
      BEGIN TRAN;

      DECLARE @SupplierId INT;
      SELECT TOP 1 @SupplierId = SupplierId FROM dbo.PriceBatchStaging WHERE BatchId = @BatchId;

      UPDATE dbo.PriceBatchLog SET Status='PROCESSING', StartedAt = ISNULL(StartedAt, SYSUTCDATETIME()) WHERE BatchId = @BatchId;

      -- 1) Brands
      INSERT dbo.Brands (Brand)
      SELECT DISTINCT s.Brand
      FROM dbo.PriceBatchStaging s
      WHERE s.BatchId = @BatchId
        AND NOT EXISTS (SELECT 1 FROM dbo.Brands b WITH (UPDLOCK,HOLDLOCK) WHERE b.Brand = s.Brand);

      -- 2) Articles
      INSERT dbo.Articles (Article)
      SELECT DISTINCT s.Article
      FROM dbo.PriceBatchStaging s
      WHERE s.BatchId = @BatchId
        AND NOT EXISTS (SELECT 1 FROM dbo.Articles a WITH (UPDLOCK,HOLDLOCK) WHERE a.Article = s.Article);

      -- 3) Sku
      INSERT dbo.Sku (BrandId, ArticleId)
      SELECT DISTINCT b.BrandId, a.ArticleId
      FROM dbo.PriceBatchStaging s
      JOIN dbo.Brands b ON b.Brand = s.Brand
      JOIN dbo.Articles a ON a.Article = s.Article
      WHERE s.BatchId = @BatchId
        AND NOT EXISTS (SELECT 1 FROM dbo.Sku sk WITH (UPDLOCK,HOLDLOCK) WHERE sk.BrandId = b.BrandId AND sk.ArticleId = a.ArticleId);

      -- 4) Полностью заменить Offers этого SupplierId
      DELETE o FROM dbo.Offers o WITH (ROWLOCK) WHERE o.SupplierId = @SupplierId;

      INSERT dbo.Offers (SupplierId, SkuId, Qty, Price)
      SELECT s.SupplierId, sk.SkuId, s.Qty, s.Price
      FROM dbo.PriceBatchStaging s
      JOIN dbo.Brands b ON b.Brand = s.Brand
      JOIN dbo.Articles a ON a.Article = s.Article
      JOIN dbo.Sku sk ON sk.BrandId = b.BrandId AND sk.ArticleId = a.ArticleId
      WHERE s.BatchId = @BatchId;

      -- 5) Descr по новым OfferId
      DELETE d FROM dbo.Descr d
      WHERE EXISTS (SELECT 1 FROM dbo.Offers o WHERE o.SupplierId = @SupplierId AND o.OfferId = d.OfferId);

      INSERT dbo.Descr (OfferId, Descr)
      SELECT o.OfferId, MAX(s.Descr)
      FROM dbo.Offers o
      JOIN dbo.PriceBatchStaging s ON s.SupplierId = o.SupplierId
      JOIN dbo.Brands b ON b.Brand = s.Brand
      JOIN dbo.Articles a ON a.Article = s.Article
      JOIN dbo.Sku sk ON sk.SkuId = o.SkuId AND sk.BrandId = b.BrandId AND sk.ArticleId = a.ArticleId
      WHERE s.BatchId = @BatchId AND o.SupplierId = @SupplierId
      GROUP BY o.OfferId;

      UPDATE dbo.PriceBatchLog SET Status='DONE', RowsOffersIns = (SELECT COUNT(*) FROM dbo.Offers WHERE SupplierId=@SupplierId), FinishedAt = SYSUTCDATETIME() WHERE BatchId = @BatchId;
      DELETE FROM dbo.PriceBatchStaging WHERE BatchId = @BatchId;

      COMMIT;
      END CONVERSATION @DlgHandle;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT > 0 ROLLBACK;
      INSERT dbo.PriceProcessErrorLog(BatchId,SupplierId,ErrorNumber,ErrorSeverity,ErrorState,ErrorProcedure,ErrorLine,ErrorMessage)
      VALUES (@BatchId,@SupplierId,ERROR_NUMBER(),ERROR_SEVERITY(),ERROR_STATE(),ERROR_PROCEDURE(),ERROR_LINE(),ERROR_MESSAGE());
      UPDATE dbo.PriceBatchLog SET Status='ERROR', ErrMsg = ERROR_MESSAGE(), FinishedAt = SYSUTCDATETIME() WHERE BatchId = @BatchId;
      DELETE FROM dbo.PriceBatchStaging WHERE BatchId = @BatchId;
      END CONVERSATION @DlgHandle;
    END CATCH
  END
END
GO
