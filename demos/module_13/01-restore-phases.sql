-- ci: skip (it reads the backups of 00-setup.sql)
-- Clip 13.1: the phases of a restore. Runs on the lab, in one session, after 00-setup.sql.
-- It restores the chain of 00-setup.sql under another name, PachadataTraining_Copy, next
-- to the database, and stops after each backup to show the state of the copy: RESTORING
-- with NORECOVERY, read-only with STANDBY, online with RECOVERY. Then the trap: a full
-- backup restored without option is recovered, and the log no longer applies.
-- The copies are dropped at the end. PachadataTraining is not touched.
USE master;
SET NOCOUNT ON;
GO
-- 1. What the backup contains: its files, then its header.
RESTORE FILELISTONLY
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak';
RESTORE HEADERONLY
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak';
GO
-- 2. The full backup, under another name, its files moved, WITH NORECOVERY.
RESTORE DATABASE PachadataTraining_Copy
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak'
    WITH MOVE N'PachadataTraining'     TO N'/var/opt/mssql/data/PachadataTraining_Copy.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/PachadataTraining_Copy_log.ldf',
         NORECOVERY;
SELECT name, state_desc, is_in_standby FROM sys.databases WHERE name = N'PachadataTraining_Copy';
GO
-- Expected error 927: the database is in the middle of a restore.
SELECT COUNT(*) AS ticks FROM PachadataTraining_Copy.dbo.RestoreClock;
GO
-- 3. The differential, WITH STANDBY: the copy can be read between two backups.
RESTORE DATABASE PachadataTraining_Copy
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_diff.bak'
    WITH STANDBY = N'/var/opt/mssql/backup/module_13/PachadataTraining_Copy_undo.tuf';
SELECT name, state_desc, is_in_standby, is_read_only FROM sys.databases WHERE name = N'PachadataTraining_Copy';
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick FROM PachadataTraining_Copy.dbo.RestoreClock;
GO
-- 4. The second log backup, still WITH STANDBY.
RESTORE LOG PachadataTraining_Copy
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log2.trn'
    WITH STANDBY = N'/var/opt/mssql/backup/module_13/PachadataTraining_Copy_undo.tuf';
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick FROM PachadataTraining_Copy.dbo.RestoreClock;
GO
-- 5. RECOVERY without a backup: the undo, and the copy is online, read and write.
RESTORE DATABASE PachadataTraining_Copy WITH RECOVERY;
SELECT name, state_desc, is_in_standby, is_read_only FROM sys.databases WHERE name = N'PachadataTraining_Copy';
SELECT name, physical_name FROM sys.master_files WHERE database_id = DB_ID(N'PachadataTraining_Copy');
GO
-- 6. The trap: the full backup restored without option, so WITH RECOVERY by default.
RESTORE DATABASE PachadataTraining_Copy2
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak'
    WITH MOVE N'PachadataTraining'     TO N'/var/opt/mssql/data/PachadataTraining_Copy2.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/PachadataTraining_Copy2_log.ldf';
GO
-- Expected error 3117: the log no longer applies, the sequence starts again from the full.
RESTORE LOG PachadataTraining_Copy2
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log1.trn'
    WITH NORECOVERY;
GO
-- 7. The copies go, with the history of their restores.
DROP DATABASE PachadataTraining_Copy;
DROP DATABASE PachadataTraining_Copy2;
GO
SELECT r.destination_database_name, r.restore_type, r.restore_date,
       RIGHT(f.physical_device_name, CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1) AS file_name
FROM msdb.dbo.restorehistory AS r
JOIN msdb.dbo.backupset AS b ON b.backup_set_id = r.backup_set_id
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE r.destination_database_name LIKE N'PachadataTraining[_]Copy%'
ORDER BY r.restore_history_id;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Copy';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Copy2';
GO
