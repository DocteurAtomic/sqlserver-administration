-- Module 6 exercise: solution of part 3, the loads. Runs on your lab, in one session, after
-- 3-solution-export.sh, which wrote the files in /var/opt/mssql/exchange/exercise_06.
-- ci: skip (it needs the files of 3-solution-export.sh)
-- It checks the two native loads, loads the text file by BULK INSERT with and without
-- KEEPIDENTITY, reads the payments of 2025 by OPENROWSET(BULK), then drops the copy
-- PachadataTraining_Ex06. T-SQL does not delete the files:
--   docker exec sqladmcourse rm -rf /var/opt/mssql/exchange/exercise_06
USE PachadataTraining_Ex06;
SET NOCOUNT ON;
GO
-- 1. The native loads of the payments since 2020. Without -E, the identity column numbered
--    the rows again from 1.
SELECT N'bcp in' AS load_type,
       (SELECT COUNT(*) FROM dbo.PaymentNative) AS loaded,
       (SELECT COUNT(*) FROM (SELECT * FROM Enrollment.Payment WHERE PaymentDate >= '20200101'
                              EXCEPT SELECT * FROM dbo.PaymentNative) AS e) AS missing
UNION ALL
SELECT N'bcp in -E',
       (SELECT COUNT(*) FROM dbo.PaymentNativeKeep),
       (SELECT COUNT(*) FROM (SELECT * FROM Enrollment.Payment WHERE PaymentDate >= '20200101'
                              EXCEPT SELECT * FROM dbo.PaymentNativeKeep) AS e);
SELECT N'source' AS payments, MIN(PaymentId) AS min_id, MAX(PaymentId) AS max_id
FROM Enrollment.Payment WHERE PaymentDate >= '20200101'
UNION ALL SELECT N'bcp in', MIN(PaymentId), MAX(PaymentId) FROM dbo.PaymentNative
UNION ALL SELECT N'bcp in -E', MIN(PaymentId), MAX(PaymentId) FROM dbo.PaymentNativeKeep;
GO
-- 2. The text file by BULK INSERT, with KEEPIDENTITY, the equivalent of -E.
DROP TABLE IF EXISTS dbo.PaymentCsv;
SELECT TOP (0) * INTO dbo.PaymentCsv FROM Enrollment.Payment;
BULK INSERT dbo.PaymentCsv
FROM N'/var/opt/mssql/exchange/exercise_06/payment.csv'
WITH (FORMAT = 'CSV', FIELDTERMINATOR = ';', KEEPIDENTITY, TABLOCK);
SELECT (SELECT COUNT(*) FROM dbo.PaymentCsv) AS loaded,
       (SELECT COUNT(*) FROM (SELECT * FROM Enrollment.Payment
                              EXCEPT SELECT * FROM dbo.PaymentCsv) AS e) AS missing,
       (SELECT COUNT(*) FROM (SELECT * FROM dbo.PaymentCsv
                              EXCEPT SELECT * FROM Enrollment.Payment) AS e) AS in_excess;
-- The empty fields (CheckNumber, SlipNumber) came back as NULL.
SELECT (SELECT COUNT(*) FROM Enrollment.Payment WHERE CheckNumber IS NULL) AS null_in_table,
       (SELECT COUNT(*) FROM dbo.PaymentCsv WHERE CheckNumber IS NULL) AS null_loaded;
GO
-- 3. The payments of 2025, read in the file with the format file, converted.
SELECT COUNT(*) AS payments_2025, SUM(CAST(f.Amount AS decimal(9, 2))) AS amount_2025
FROM OPENROWSET(BULK N'/var/opt/mssql/exchange/exercise_06/payment.csv',
                FORMATFILE = N'/var/opt/mssql/exchange/exercise_06/payment.fmt') AS f
WHERE CAST(f.PaymentDate AS date) >= '20250101' AND CAST(f.PaymentDate AS date) < '20260101';
SELECT COUNT(*) AS payments_2025, SUM(Amount) AS amount_2025
FROM Enrollment.Payment
WHERE PaymentDate >= '20250101' AND PaymentDate < '20260101';
GO
-- 4. The copy of the exercise goes, with its tables.
USE master;
ALTER DATABASE PachadataTraining_Ex06 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex06;
SELECT name FROM sys.databases WHERE name LIKE N'PachadataTraining_Ex06%';
GO
