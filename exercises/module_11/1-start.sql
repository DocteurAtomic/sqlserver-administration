-- Module 11 exercise: start. Runs on your lab, in one session, after setup/install.sh
-- (Ola Hallengren's scripts in the database DBA). About ten seconds.
-- Restores a copy of the database, PachadataTraining_Ex11, which stands for the accounting
-- database, and adds to it dbo.PaymentArchive, a copy of Enrollment.Payment, then damages one
-- data page of that copy on disk with DBCC WRITEPAGE (undocumented, test databases only).
-- The exercise never writes in PachadataTraining. 3-solution-maintenance.sql deletes what the
-- exercise creates, the copy included.
USE master;
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'DBA.dbo.IndexOptimize') IS NULL
    RAISERROR (N'DBA.dbo.IndexOptimize is missing: run ./setup/install-ola.sh first.', 16, 1);
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex11';
GO
SELECT PaymentId, InvoiceCode, PaymentDate, Amount, PaymentMethodCode
INTO PachadataTraining_Ex11.dbo.PaymentArchive
FROM PachadataTraining_Ex11.Enrollment.Payment;
ALTER TABLE PachadataTraining_Ex11.dbo.PaymentArchive
    ADD CONSTRAINT pk_PaymentArchive PRIMARY KEY CLUSTERED (PaymentId);
GO
-- The data page that holds payment 50000, damaged on disk. %%physloc%% (undocumented) gives
-- the file, page and slot of a row.
DECLARE @page int = (
    SELECT l.page_id
    FROM PachadataTraining_Ex11.dbo.PaymentArchive AS p
    CROSS APPLY sys.fn_PhysLocCracker(p.%%physloc%%) AS l
    WHERE p.PaymentId = 50000);
ALTER DATABASE PachadataTraining_Ex11 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC WRITEPAGE (N'PachadataTraining_Ex11', 1, @page, 2000, 2, 0x4141, 1);
ALTER DATABASE PachadataTraining_Ex11 SET MULTI_USER;
GO
SELECT name, recovery_model_desc, DATABASEPROPERTYEX(name, 'LastGoodCheckDbTime') AS last_good_checkdb
FROM sys.databases
WHERE name = N'PachadataTraining_Ex11';
GO
