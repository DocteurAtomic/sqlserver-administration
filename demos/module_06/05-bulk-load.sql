-- Clip 6.2: loading the files back, by BULK INSERT and OPENROWSET(BULK). Runs on the lab, in
-- one session, after 04-export.sh, which wrote the files in /var/opt/mssql/exchange.
-- ci: skip (it needs the files of 04-export.sh, and part 2 ends on an expected error)
-- Run it part by part (select a part, then F5): parts 2 and 6 fail on purpose.
-- The server reads the files itself, under its own account (mssql on Linux): the paths are
-- those of the server, not of the machine where SSMS runs.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. An empty table with the columns of Enrollment.Invoice, without its keys and constraints.
DROP TABLE IF EXISTS dbo.InvoiceLoad;
SELECT TOP (0) * INTO dbo.InvoiceLoad FROM Enrollment.Invoice;
GO
-- 2. The file with commas: the comma inside a reason shifts the fields (error 4879).
BULK INSERT dbo.InvoiceLoad
FROM N'/var/opt/mssql/exchange/invoice_comma.csv'
WITH (FORMAT = 'CSV', FIELDTERMINATOR = ',', TABLOCK);
GO
-- 3. The file with semicolons.
TRUNCATE TABLE dbo.InvoiceLoad;
BULK INSERT dbo.InvoiceLoad
FROM N'/var/opt/mssql/exchange/invoice.csv'
WITH (FORMAT = 'CSV', FIELDTERMINATOR = ';', TABLOCK);
GO
-- 4. Nothing missing, nothing in excess: EXCEPT in both directions.
SELECT (SELECT COUNT(*) FROM dbo.InvoiceLoad) AS loaded,
       (SELECT COUNT(*) FROM (SELECT * FROM Enrollment.Invoice
                              EXCEPT SELECT * FROM dbo.InvoiceLoad) AS e) AS missing,
       (SELECT COUNT(*) FROM (SELECT * FROM dbo.InvoiceLoad
                              EXCEPT SELECT * FROM Enrollment.Invoice) AS e) AS in_excess;
-- The NULLs went out as empty fields and came back as NULLs.
SELECT (SELECT COUNT(*) FROM Enrollment.Invoice WHERE OrderReference IS NULL) AS null_in_table,
       (SELECT COUNT(*) FROM dbo.InvoiceLoad WHERE OrderReference IS NULL) AS null_loaded;
GO
-- 5. The file read as a table, with its format file: the invoices of 2026 only. Every field
--    of a character format file is SQLCHAR, so OPENROWSET returns varchar: the conversions
--    are needed.
SELECT COUNT(*) AS invoices_2026, SUM(CAST(f.GrossAmount AS decimal(9, 2))) AS gross_2026
FROM OPENROWSET(BULK N'/var/opt/mssql/exchange/invoice.csv',
                FORMATFILE = N'/var/opt/mssql/exchange/invoice.fmt') AS f
WHERE CAST(f.InvoiceDate AS date) >= '20260101';
SELECT COUNT(*) AS invoices_2026, SUM(GrossAmount) AS gross_2026
FROM Enrollment.Invoice
WHERE InvoiceDate >= '20260101';
GO
-- 6. Without the conversion, the comparison fails (error 245).
SELECT COUNT(*) AS large_invoices
FROM OPENROWSET(BULK N'/var/opt/mssql/exchange/invoice.csv',
                FORMATFILE = N'/var/opt/mssql/exchange/invoice.fmt') AS f
WHERE f.GrossAmount > 5000;
GO
-- 7. The load table goes; the files stay for clip 6.3.
DROP TABLE dbo.InvoiceLoad;
GO
