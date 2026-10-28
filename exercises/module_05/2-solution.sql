-- Module 5 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- It takes about a minute, and drops at the end the copy PachadataTraining_Ex05.
-- The expected errors are caught by TRY ... CATCH, which shows their number and message.
USE PachadataTraining_Ex05;
SET NOCOUNT ON;
GO
-- Part 1. A heap and its forwarded records.
-- 1.1 The state before: pages, rows, forwarded records, fullness of the pages.
SELECT page_count, record_count, forwarded_record_count,
       CAST(avg_page_space_used_in_percent AS decimal(5, 2)) AS page_fullness_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Contact.ProspectUS_N'), 0, NULL, 'DETAILED');
-- 1.2 The update that lengthens the rows.
UPDATE Contact.ProspectUS_N
SET City = City + N' (billing address distinct from head office)'
WHERE Phone LIKE N'%7';
SELECT @@ROWCOUNT AS prospects_updated;
SELECT page_count, record_count, forwarded_record_count,
       CAST(avg_page_space_used_in_percent AS decimal(5, 2)) AS page_fullness_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Contact.ProspectUS_N'), 0, NULL, 'DETAILED');
-- 1.3 The count, with the pages read.
SET STATISTICS IO ON;
SELECT COUNT(*) AS first_name_j FROM Contact.ProspectUS_N WHERE FirstName LIKE N'J%';
SET STATISTICS IO OFF;
-- 1.4 The rebuild, and the same count.
ALTER TABLE Contact.ProspectUS_N REBUILD;
SELECT page_count, record_count, forwarded_record_count,
       CAST(avg_page_space_used_in_percent AS decimal(5, 2)) AS page_fullness_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Contact.ProspectUS_N'), 0, NULL, 'DETAILED');
SET STATISTICS IO ON;
SELECT COUNT(*) AS first_name_j FROM Contact.ProspectUS_N WHERE FirstName LIKE N'J%';
SET STATISTICS IO OFF;
GO
-- Part 2. Constraints, identities, sequences.
-- 2.1 The constraints the engine no longer trusts.
SELECT N'FOREIGN KEY' AS constraint_type, OBJECT_SCHEMA_NAME(parent_object_id) + N'.'
       + OBJECT_NAME(parent_object_id) AS table_name, name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE is_not_trusted = 1
UNION ALL
SELECT N'CHECK', OBJECT_SCHEMA_NAME(parent_object_id) + N'.' + OBJECT_NAME(parent_object_id),
       name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE is_not_trusted = 1;
-- 2.2 The two queries, before the correction. The partitioned view dbo.InvoiceAll joins
--     Enrollment.InvoiceHistory (before September 2010) and Enrollment.Invoice (from
--     September 2010); only the check constraints say so to the optimizer.
SET STATISTICS IO ON;
SELECT COUNT(*) AS invoices_before_2010 FROM dbo.InvoiceAll WHERE InvoiceDate < '2010-01-01';
SELECT COUNT(*) AS invoice_lines
FROM Enrollment.InvoiceLine AS il
JOIN Enrollment.Invoice AS i ON i.InvoiceCode = il.InvoiceCode;
SET STATISTICS IO OFF;
GO
-- 2.3 The correction, and the same queries.
ALTER TABLE Enrollment.Invoice WITH CHECK CHECK CONSTRAINT chk_Invoice_InvoiceDate;
ALTER TABLE Enrollment.InvoiceLine WITH CHECK CHECK CONSTRAINT fk_InvoiceLine_Invoice;
SELECT name, is_not_trusted FROM sys.check_constraints WHERE name = N'chk_Invoice_InvoiceDate'
UNION ALL
SELECT name, is_not_trusted FROM sys.foreign_keys WHERE name = N'fk_InvoiceLine_Invoice';
SET STATISTICS IO ON;
SELECT COUNT(*) AS invoices_before_2010 FROM dbo.InvoiceAll WHERE InvoiceDate < '2010-01-01';
SELECT COUNT(*) AS invoice_lines
FROM Enrollment.InvoiceLine AS il
JOIN Enrollment.Invoice AS i ON i.InvoiceCode = il.InvoiceCode;
SET STATISTICS IO OFF;
GO
-- 2.4 The foreign keys of the invoicing tables whose column leads no index.
SELECT OBJECT_SCHEMA_NAME(fkc.parent_object_id) + N'.' + OBJECT_NAME(fkc.parent_object_id) AS table_name,
       fk.name AS foreign_key, COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS column_name
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
WHERE fkc.parent_object_id IN (OBJECT_ID(N'Enrollment.Invoice'), OBJECT_ID(N'Enrollment.InvoiceLine'),
                               OBJECT_ID(N'Enrollment.Payment'))
  AND NOT EXISTS (SELECT 1 FROM sys.index_columns AS ic
                  WHERE ic.object_id = fkc.parent_object_id
                    AND ic.column_id = fkc.parent_column_id
                    AND ic.key_ordinal = 1)
ORDER BY table_name, foreign_key;
GO
-- 2.5 A sequence for the credit note numbers, and a number taken in a transaction that is
--     rolled back.
CREATE SEQUENCE Enrollment.CreditNoteNumber AS int START WITH 1 INCREMENT BY 1;
BEGIN TRANSACTION;
SELECT NEXT VALUE FOR Enrollment.CreditNoteNumber AS number_taken;
ROLLBACK;
SELECT NEXT VALUE FOR Enrollment.CreditNoteNumber AS next_number;
SELECT name, start_value, current_value FROM sys.sequences WHERE name = N'CreditNoteNumber';
DROP SEQUENCE Enrollment.CreditNoteNumber;
GO
-- Part 3. Compression of the prospects in nvarchar.
-- 3.1 The estimates.
EXEC sys.sp_estimate_data_compression_savings
     @schema_name = N'Contact', @object_name = N'ProspectUS_N', @index_id = 0,
     @partition_number = NULL, @data_compression = N'ROW';
EXEC sys.sp_estimate_data_compression_savings
     @schema_name = N'Contact', @object_name = N'ProspectUS_N', @index_id = 0,
     @partition_number = NULL, @data_compression = N'PAGE';
-- 3.2 ROW, then PAGE, measured after each rebuild.
ALTER TABLE Contact.ProspectUS_N REBUILD WITH (DATA_COMPRESSION = ROW);
SELECT p.data_compression_desc, ps.used_page_count, ps.used_page_count * 8 AS used_kb
FROM sys.dm_db_partition_stats AS ps
JOIN sys.partitions AS p ON p.partition_id = ps.partition_id
WHERE ps.object_id = OBJECT_ID(N'Contact.ProspectUS_N');
ALTER TABLE Contact.ProspectUS_N REBUILD WITH (DATA_COMPRESSION = PAGE);
SELECT p.data_compression_desc, ps.used_page_count, ps.used_page_count * 8 AS used_kb
FROM sys.dm_db_partition_stats AS ps
JOIN sys.partitions AS p ON p.partition_id = ps.partition_id
WHERE ps.object_id = OBJECT_ID(N'Contact.ProspectUS_N');
-- The varchar twin, not compressed, for comparison.
SELECT used_page_count, used_page_count * 8 AS used_kb
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Contact.ProspectUS_SQL_Latin1');
GO
-- Part 4. A partitioned copy of the invoices, and its sliding window.
-- 4.1 The function, one boundary per year from 2010 to 2027, and the scheme.
CREATE PARTITION FUNCTION pfInvoiceYear (smalldatetime)
AS RANGE RIGHT FOR VALUES ('2010-01-01', '2011-01-01', '2012-01-01', '2013-01-01', '2014-01-01',
                           '2015-01-01', '2016-01-01', '2017-01-01', '2018-01-01', '2019-01-01',
                           '2020-01-01', '2021-01-01', '2022-01-01', '2023-01-01', '2024-01-01',
                           '2025-01-01', '2026-01-01', '2027-01-01');
CREATE PARTITION SCHEME psInvoiceYear AS PARTITION pfInvoiceYear ALL TO ([PRIMARY]);
GO
-- 4.2 A primary key without the partitioning column is refused. Run alone, the statement
--     returns two errors: 1908 "Column 'CreationDate' is partitioning column of the index
--     'PK_InvoiceByYear'. Partition columns for a unique index must be a subset of the index
--     key.", then 1750. CATCH only keeps the last one.
BEGIN TRY
    CREATE TABLE dbo.InvoiceByYear (
        InvoiceCode  varchar(50)   NOT NULL,
        CreationDate smalldatetime NOT NULL,
        CompanyId    int           NULL,
        ContactId    int           NULL,
        NetAmount    decimal(9, 2) NOT NULL,
        CONSTRAINT PK_InvoiceByYear PRIMARY KEY CLUSTERED (InvoiceCode)
    ) ON psInvoiceYear (CreationDate);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
CREATE TABLE dbo.InvoiceByYear (
    InvoiceCode  varchar(50)   NOT NULL,
    CreationDate smalldatetime NOT NULL,
    CompanyId    int           NULL,
    ContactId    int           NULL,
    NetAmount    decimal(9, 2) NOT NULL,
    CONSTRAINT PK_InvoiceByYear PRIMARY KEY CLUSTERED (InvoiceCode, CreationDate)
) ON psInvoiceYear (CreationDate);
INSERT INTO dbo.InvoiceByYear (InvoiceCode, CreationDate, CompanyId, ContactId, NetAmount)
SELECT InvoiceCode, CreationDate, CompanyId, ContactId, NetAmount
FROM Enrollment.Invoice;
GO
-- 4.3 The partitions, and $PARTITION.
SELECT p.partition_number, prv.value AS lower_boundary, p.rows
FROM sys.partitions AS p
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = (SELECT function_id FROM sys.partition_functions WHERE name = N'pfInvoiceYear')
      AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'dbo.InvoiceByYear') AND p.index_id = 1
ORDER BY p.partition_number;
SELECT $PARTITION.pfInvoiceYear('2009-12-31') AS p_2009_12_31, $PARTITION.pfInvoiceYear('2010-01-01') AS p_2010_01_01,
       $PARTITION.pfInvoiceYear('2015-06-15') AS p_2015_06_15, $PARTITION.pfInvoiceYear('2030-01-01') AS p_2030_01_01;
GO
-- 4.4 The archive table: same columns, same clustered key, same filegroup.
CREATE TABLE dbo.InvoiceArchive (
    InvoiceCode  varchar(50)   NOT NULL,
    CreationDate smalldatetime NOT NULL,
    CompanyId    int           NULL,
    ContactId    int           NULL,
    NetAmount    decimal(9, 2) NOT NULL,
    CONSTRAINT PK_InvoiceArchive PRIMARY KEY CLUSTERED (InvoiceCode, CreationDate)
) ON [PRIMARY];
-- 4.5 An index that is not aligned blocks SWITCH and TRUNCATE ... WITH (PARTITIONS).
CREATE INDEX ix_InvoiceByYear_CompanyId ON dbo.InvoiceByYear (CompanyId) ON [PRIMARY];
BEGIN TRY
    ALTER TABLE dbo.InvoiceByYear
        SWITCH PARTITION $PARTITION.pfInvoiceYear('2010-01-01') TO dbo.InvoiceArchive;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
BEGIN TRY
    TRUNCATE TABLE dbo.InvoiceByYear WITH (PARTITIONS ($PARTITION.pfInvoiceYear('2011-01-01')));
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
CREATE INDEX ix_InvoiceByYear_CompanyId ON dbo.InvoiceByYear (CompanyId)
    WITH (DROP_EXISTING = ON) ON psInvoiceYear (CreationDate);
SELECT i.name AS index_name, ds.name AS data_space, ds.type_desc
FROM sys.indexes AS i
JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'dbo.InvoiceByYear');
GO
-- 4.6 The sliding window. Each operation runs in a transaction, to read its log records.
-- Open 2028.
ALTER PARTITION SCHEME psInvoiceYear NEXT USED [PRIMARY];
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfInvoiceYear() SPLIT RANGE ('2028-01-01');
SELECT N'SPLIT 2028' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
-- Archive 2010.
BEGIN TRANSACTION;
ALTER TABLE dbo.InvoiceByYear
    SWITCH PARTITION $PARTITION.pfInvoiceYear('2010-01-01') TO dbo.InvoiceArchive;
SELECT N'SWITCH 2010' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
-- Purge 2011.
BEGIN TRANSACTION;
TRUNCATE TABLE dbo.InvoiceByYear WITH (PARTITIONS ($PARTITION.pfInvoiceYear('2011-01-01')));
SELECT N'TRUNCATE 2011' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
-- Remove the two boundaries: each one sits between two empty partitions.
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfInvoiceYear() MERGE RANGE ('2010-01-01');
ALTER PARTITION FUNCTION pfInvoiceYear() MERGE RANGE ('2011-01-01');
SELECT N'MERGE 2010 and 2011' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
GO
-- 4.7 For comparison: a boundary cut inside a full partition, then removed.
ALTER PARTITION SCHEME psInvoiceYear NEXT USED [PRIMARY];
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfInvoiceYear() SPLIT RANGE ('2025-07-01');
SELECT N'SPLIT 2025-07-01' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfInvoiceYear() MERGE RANGE ('2025-07-01');
SELECT N'MERGE 2025-07-01' AS operation, SUM(database_transaction_log_record_count) AS log_records
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
GO
-- 4.8 The result.
SELECT p.partition_number, prv.value AS lower_boundary, p.rows
FROM sys.partitions AS p
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = (SELECT function_id FROM sys.partition_functions WHERE name = N'pfInvoiceYear')
      AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'dbo.InvoiceByYear') AND p.index_id = 1
ORDER BY p.partition_number;
SELECT COUNT(*) AS archived_invoices, MIN(CreationDate) AS first_date, MAX(CreationDate) AS last_date
FROM dbo.InvoiceArchive;
GO
-- Cleanup: the copy of the database.
USE master;
GO
ALTER DATABASE PachadataTraining_Ex05 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex05;
GO
