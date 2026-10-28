-- ci: skip (it reads the chain of 00-setup.sql and 02-data-file-loss.sql)
-- Clip 13.3: the human error. Runs on the lab, in one session, after 02-data-file-loss.sql.
-- A developer empties Enrollment.Payment by mistake. The chain is restored next to the
-- database, under the name PachadataTraining_PIT, up to one second before the DELETE
-- (STOPAT), and the lost rows are copied back. Everything entered since is kept.
-- The time of the error is written in tempdb, which the restore does not touch:
-- in real life, it is the time the developer gives, or the clock of the database.
USE master;
SET NOCOUNT ON;
GO
-- 1. The error.
SELECT COUNT(*) AS payments FROM PachadataTraining.Enrollment.Payment;
DROP TABLE IF EXISTS tempdb.dbo.Module13Incident;
SELECT SYSDATETIME() AS ErrorAt INTO tempdb.dbo.Module13Incident;
DELETE FROM PachadataTraining.Enrollment.Payment;
SELECT ErrorAt FROM tempdb.dbo.Module13Incident;
GO
-- 2. Life goes on: a new payment comes in after the error, then the log backup of the
--    next quarter of an hour.
INSERT INTO PachadataTraining.Enrollment.Payment (InvoiceCode, PaymentDate, Amount, PaymentMethodCode)
VALUES ('FA2026-007229', '20261028', 120.00, 'WIRE');
WAITFOR DELAY '00:00:05';
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log3.trn'
    WITH INIT, FORMAT, CHECKSUM;
GO
-- 3. The log backups since the restore of clip 13.2, and where each one can stop.
SELECT b.type, b.is_copy_only, b.first_lsn, b.last_lsn, b.last_valid_restore_time,
       RIGHT(f.physical_device_name, CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1) AS file_name
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining' AND b.server_name = @@SERVERNAME
  AND b.type = 'L'
ORDER BY b.backup_set_id;
GO
-- 4. The restore next to the database, up to one second before the error. The tail of
--    clip 13.2 is not in the sequence: it was copy-only, and log 3 starts where log 2 ends.
--    STOPAT takes a datetime, not a datetime2.
DECLARE @stopat datetime = (SELECT DATEADD(SECOND, -1, ErrorAt) FROM tempdb.dbo.Module13Incident);
SELECT @stopat AS stop_at;
RESTORE DATABASE PachadataTraining_PIT
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak'
    WITH MOVE N'PachadataTraining'     TO N'/var/opt/mssql/data/PachadataTraining_PIT.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/PachadataTraining_PIT_log.ldf',
         NORECOVERY;
RESTORE DATABASE PachadataTraining_PIT
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_diff.bak' WITH NORECOVERY;
RESTORE LOG PachadataTraining_PIT
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log2.trn' WITH NORECOVERY;
RESTORE LOG PachadataTraining_PIT
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log3.trn'
    WITH STOPAT = @stopat, RECOVERY;
GO
-- 5. The two databases side by side.
SELECT (SELECT COUNT(*) FROM PachadataTraining_PIT.Enrollment.Payment) AS payments_in_copy,
       (SELECT COUNT(*) FROM PachadataTraining.Enrollment.Payment)     AS payments_in_database,
       (SELECT MAX(At) FROM PachadataTraining_PIT.dbo.RestoreClock)    AS last_tick_in_copy,
       (SELECT MAX(At) FROM PachadataTraining.dbo.RestoreClock)        AS last_tick_in_database;
GO
-- 6. The lost rows go back, with their identifiers: the invoices refer to them by number.
--    The payment entered after the error has its own identifier, after the lost ones.
SET IDENTITY_INSERT PachadataTraining.Enrollment.Payment ON;
INSERT INTO PachadataTraining.Enrollment.Payment
       (PaymentId, InvoiceCode, PaymentDate, CheckNumber, SlipNumber, Amount, PaymentMethodCode)
SELECT c.PaymentId, c.InvoiceCode, c.PaymentDate, c.CheckNumber, c.SlipNumber, c.Amount, c.PaymentMethodCode
FROM PachadataTraining_PIT.Enrollment.Payment AS c
WHERE NOT EXISTS (SELECT * FROM PachadataTraining.Enrollment.Payment AS p
                  WHERE p.PaymentId = c.PaymentId);
SET IDENTITY_INSERT PachadataTraining.Enrollment.Payment OFF;
GO
SELECT COUNT(*) AS payments, MAX(PaymentId) AS last_payment_id
FROM PachadataTraining.Enrollment.Payment;
SELECT TOP (2) PaymentId, InvoiceCode, PaymentDate, Amount
FROM PachadataTraining.Enrollment.Payment ORDER BY PaymentId DESC;
GO
-- 7. The copy goes.
DROP DATABASE PachadataTraining_PIT;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_PIT';
GO
