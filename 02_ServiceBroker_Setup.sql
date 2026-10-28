-- 02_ServiceBroker_Setup.sql
-- Включаем Service Broker при необходимости (аккуратно на проде)
-- ALTER DATABASE [ECommerce] SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE;

IF NOT EXISTS (SELECT 1 FROM sys.service_message_types WHERE name = 'http://ecommerce/prices/PriceBatch')
    CREATE MESSAGE TYPE [http://ecommerce/prices/PriceBatch] VALIDATION = WELL_FORMED_XML;

IF NOT EXISTS (SELECT 1 FROM sys.service_contracts WHERE name = 'http://ecommerce/prices/PriceBatchContract')
    CREATE CONTRACT [http://ecommerce/prices/PriceBatchContract] ([http://ecommerce/prices/PriceBatch] SENT BY INITIATOR);

IF NOT EXISTS (SELECT 1 FROM sys.service_queues WHERE name = 'dbo.PriceBatchQueue')
    CREATE QUEUE dbo.PriceBatchQueue WITH STATUS = ON, RETENTION = OFF, ACTIVATION (
      STATUS = ON,
      PROCEDURE_NAME = dbo.sp_ProcessSupplierBatch,
      MAX_QUEUE_READERS = 8,
      EXECUTE AS SELF
    );

IF NOT EXISTS (SELECT 1 FROM sys.services WHERE name = 'http://ecommerce/prices/PriceBatchService')
    CREATE SERVICE [http://ecommerce/prices/PriceBatchService] ON QUEUE dbo.PriceBatchQueue ([http://ecommerce/prices/PriceBatchContract]);
GO
