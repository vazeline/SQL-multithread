-- 00_Create_Tables.sql
USE [ECommerce];
GO

-- Справочник поставщиков
IF OBJECT_ID('dbo.Suppliers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Suppliers
    (
        SupplierId   INT          NOT NULL PRIMARY KEY,
        SupplierName NVARCHAR(255) NULL
    );
END
GO

-- Справочник брендов
IF OBJECT_ID('dbo.Brands', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Brands
    (
        BrandId INT          IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Brand   VARCHAR(255) NOT NULL
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_Brands_Brand ON dbo.Brands(Brand);
END
GO

-- Справочник артикулов
IF OBJECT_ID('dbo.Articles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Articles
    (
        ArticleId BIGINT       IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Article   VARCHAR(255) NOT NULL
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_Articles_Article ON dbo.Articles(Article);
END
GO

-- Карточки товаров (связка бренд-артикул)
IF OBJECT_ID('dbo.Sku', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sku
    (
        SkuId     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        BrandId   INT    NOT NULL,
        ArticleId BIGINT NOT NULL,
        CONSTRAINT FK_Sku_Brands   FOREIGN KEY (BrandId)   REFERENCES dbo.Brands(BrandId),
        CONSTRAINT FK_Sku_Articles FOREIGN KEY (ArticleId) REFERENCES dbo.Articles(ArticleId)
    );

    CREATE UNIQUE NONCLUSTERED INDEX IX_Sku_BrandArticle ON dbo.Sku(BrandId, ArticleId);
END
GO

-- Актуальные предложения (прайс-листы) поставщиков
IF OBJECT_ID('dbo.Offers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Offers
    (
        OfferId    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        SupplierId INT    NOT NULL,
        SkuId      BIGINT NOT NULL,
        Qty        INT    NOT NULL,
        Price      MONEY  NOT NULL,
        CONSTRAINT FK_Offers_Suppliers FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId),
        CONSTRAINT FK_Offers_Sku       FOREIGN KEY (SkuId)       REFERENCES dbo.Sku(SkuId)
    );

    CREATE NONCLUSTERED INDEX IX_Offers_SupplierId ON dbo.Offers(SupplierId) INCLUDE (SkuId, Qty, Price, OfferId);
    CREATE NONCLUSTERED INDEX IX_Offers_SkuId      ON dbo.Offers(SkuId);
END
GO

-- Названия/описания товаров по предложению
IF OBJECT_ID('dbo.Descr', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Descr
    (
        OfferId BIGINT       NOT NULL PRIMARY KEY,
        Descr   VARCHAR(MAX) NULL,
        CONSTRAINT FK_Descr_Offers FOREIGN KEY (OfferId) REFERENCES dbo.Offers(OfferId) ON DELETE CASCADE
    );
END
GO

-- Входная таблица для загрузки свежих прайс-листов от поставщиков
IF OBJECT_ID('dbo.Prices', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Prices
    (
        SupplierId INT          NOT NULL,
        Brand      VARCHAR(255) NOT NULL,
        Article    VARCHAR(255) NOT NULL,
        Qty        INT          NOT NULL,
        Price      MONEY        NOT NULL,
        Descr      VARCHAR(MAX) NULL
    );

    CREATE NONCLUSTERED INDEX IX_Prices_Supplier ON dbo.Prices(SupplierId);
    CREATE NONCLUSTERED INDEX IX_Prices_BrandArticle ON dbo.Prices(Brand, Article);
END
GO