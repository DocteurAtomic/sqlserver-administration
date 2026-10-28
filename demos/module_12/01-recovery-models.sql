-- Clip 12.1: the recovery models. Runs on the lab, in one session, after 00-setup.sql.
-- ci: skip (parts 2 and 3 end on an expected error, which stops sqlcmd -b)
-- Run it part by part (select a part, then F5): parts 2 and 3 fail on purpose.
-- The load of parts 4 and 6 stands for a day of invoicing: two updates of the 250,198
-- lines of Enrollment.InvoiceLine, the second one putting the labels back.
USE master;
SET NOCOUNT ON;
GO
-- 1. The recovery model of each database, the last log backup, and what the log waits for.
SELECT d.name, d.recovery_model_desc, rs.last_log_backup_lsn, d.log_reuse_wait_desc
FROM sys.databases AS d
JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
ORDER BY d.database_id;
GO
-- 2. In SIMPLE, a log backup is refused (error 4208).
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_log_0.trn';
GO
-- 3. In FULL, before any full backup, it is still refused (error 4214).
ALTER DATABASE PachadataTraining SET RECOVERY FULL;
SELECT d.name, d.recovery_model_desc, rs.last_log_backup_lsn
FROM sys.databases AS d
JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
WHERE d.name = N'PachadataTraining';
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_log_0.trn';
GO
-- 4. FULL without a full backup: the load, then a checkpoint. The log space used, not the
--    size of the file (preallocated at 1,200 MB).
USE PachadataTraining;
SET NOCOUNT ON;
SELECT N'before the load' AS moment, total_log_size_in_bytes / 1048576 AS log_file_mb,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label);
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label);
SELECT N'after the load' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
CHECKPOINT;
SELECT N'after a checkpoint' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME();
GO
-- 5. The first full backup opens the log chain.
USE master;
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_full_0.bak'
    WITH CHECKSUM;
SELECT d.name, d.recovery_model_desc, rs.last_log_backup_lsn
FROM sys.databases AS d
JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
WHERE d.name = N'PachadataTraining';
GO
-- 6. The same load, the same checkpoint.
USE PachadataTraining;
SET NOCOUNT ON;
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label);
UPDATE Enrollment.InvoiceLine SET Label = REVERSE(Label);
SELECT N'after the load' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
CHECKPOINT;
SELECT N'after a checkpoint' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME();
GO
-- 7. The log backup copies the log, then truncates it.
USE master;
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_log_1.trn'
    WITH CHECKSUM;
USE PachadataTraining;
SELECT N'after the log backup' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME();
GO
