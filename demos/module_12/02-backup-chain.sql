-- Clip 12.2: full, differential and log backups. Runs on the lab, in one session, after
-- 01-recovery-models.sql (it also runs alone: part 1 puts the database in FULL).
-- One file per backup, in /var/opt/mssql/backup/module_12. A clock table marks the
-- moment of each backup: a point-in-time restore aims at such a moment.
USE master;
SET NOCOUNT ON;
GO
-- 1. The clock table.
ALTER DATABASE PachadataTraining SET RECOVERY FULL;
GO
USE PachadataTraining;
DROP TABLE IF EXISTS dbo.BackupClock;
CREATE TABLE dbo.BackupClock (
    ClockId int IDENTITY PRIMARY KEY,
    Label   varchar(50) NOT NULL,
    At      datetime2(3) NOT NULL DEFAULT SYSDATETIME()
);
GO
-- 2. A full backup.
USE master;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before full');
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_full.bak'
    WITH INIT, FORMAT, CHECKSUM;
GO
-- 3. A small change (one more reminder on the 74 invoices of 2010), then what a differential would
--    copy, the differential itself, and a log backup.
USE PachadataTraining;
UPDATE Enrollment.Invoice
SET ReminderLevel = ReminderLevel + 1
WHERE DocumentType = 'I' AND InvoiceDate < '20110101';
SELECT modified_extent_page_count FROM sys.dm_db_file_space_usage;
USE master;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before diff 1');
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_diff1.bak'
    WITH DIFFERENTIAL, INIT, FORMAT, CHECKSUM;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before log 1');
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_log1.trn'
    WITH INIT, FORMAT, CHECKSUM;
GO
-- 4. A larger change (the labels of the 18,226 invoice lines of 2025, twice, back to where they
--    were), the second differential, a copy-only full backup, and a second log backup.
USE PachadataTraining;
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label) WHERE InvoiceCode LIKE 'FA2025%';
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label) WHERE InvoiceCode LIKE 'FA2025%';
SELECT modified_extent_page_count FROM sys.dm_db_file_space_usage;
USE master;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before diff 2');
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_diff2.bak'
    WITH DIFFERENTIAL, INIT, FORMAT, CHECKSUM;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before copy-only');
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_copy.bak'
    WITH COPY_ONLY, INIT, FORMAT, CHECKSUM;
INSERT INTO PachadataTraining.dbo.BackupClock (Label) VALUES ('before log 2');
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_log2.trn'
    WITH INIT, FORMAT, CHECKSUM;
GO
-- 5. The base of the differentials, for the data file.
SELECT name, differential_base_lsn, differential_base_time
FROM sys.master_files
WHERE database_id = DB_ID(N'PachadataTraining') AND type_desc = N'ROWS';
GO
-- 6. The history in msdb: every backup set of the database, then only those of this server.
SELECT b.server_name, b.type, b.is_copy_only,
       CAST(b.backup_size / 1048576.0 AS decimal(9, 1)) AS size_mb,
       b.first_lsn, b.last_lsn, b.database_backup_lsn, b.differential_base_lsn,
       f.physical_device_name
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining'
ORDER BY b.backup_set_id;

SELECT b.type, b.is_copy_only,
       CAST(b.backup_size / 1048576.0 AS decimal(9, 1)) AS size_mb,
       b.first_lsn, b.last_lsn, b.differential_base_lsn,
       RIGHT(f.physical_device_name, CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1) AS file_name
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining'
  AND b.server_name = @@SERVERNAME
ORDER BY b.backup_set_id;
GO
-- 7. The clock.
SELECT ClockId, Label, At FROM PachadataTraining.dbo.BackupClock ORDER BY ClockId;
GO
