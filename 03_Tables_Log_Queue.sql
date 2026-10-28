-- 03_Tables_Log_Queue.sql
IF OBJECT_ID('dbo.PriceBatchLog','U') IS NULL
CREATE TABLE dbo.PriceBatchLog (
  BatchId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWID(),
  SupplierId INT NOT NULL,
  Status VARCHAR(20) NOT NULL, -- ENQUEUED/PROCESSING/DONE/ERROR
  RowsIn INT NULL,
  RowsOffersIns INT NULL,
  StartedAt DATETIME2 NULL,
  FinishedAt DATETIME2 NULL,
  ErrMsg NVARCHAR(MAX) NULL
);

IF OBJECT_ID('dbo.PriceProcessErrorLog','U') IS NULL
CREATE TABLE dbo.PriceProcessErrorLog (
  Id BIGINT IDENTITY(1,1) PRIMARY KEY,
  BatchId UNIQUEIDENTIFIER NULL,
  SupplierId INT NULL,
  ErrorNumber INT NULL,
  ErrorSeverity INT NULL,
  ErrorState INT NULL,
  ErrorProcedure NVARCHAR(128) NULL,
  ErrorLine INT NULL,
  ErrorMessage NVARCHAR(MAX) NULL,
  LogAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dbo.PriceBatchStaging','U') IS NULL
CREATE TABLE dbo.PriceBatchStaging (
  BatchId UNIQUEIDENTIFIER NOT NULL,
  SupplierId INT NOT NULL,
  Brand VARCHAR(255) NOT NULL,
  Article VARCHAR(255) NOT NULL,
  Qty INT NOT NULL,
  Price MONEY NOT NULL,
  Descr VARCHAR(MAX) NULL,
  RowNum INT IDENTITY(1,1)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PBS_Batch')
    CREATE INDEX IX_PBS_Batch ON dbo.PriceBatchStaging(BatchId);
GO
