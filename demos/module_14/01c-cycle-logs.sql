-- Clip 14.1: recycle the two logs, and silence the successful backups. Played for the video
-- on the throwaway container sqladm-14:
-- ci: skip (it closes the current error log and sets a global trace flag, instance changes)
-- On your lab, run it in one go after 01a-read-logs.sql; 99-cleanup.sql turns the trace
-- flag off. A recycled log cannot be put back: it stays an archive, which is harmless.
-- 1. Recycle the error log and the Agent log without a restart: the failed connections of
--    01b-events.sh are now in archive 1.
-- 2. Two copy-only backups of DBA, in /var/opt/mssql/backup/module_14, each one over the
--    previous file (INIT): each one adds a line "Database backed up" to the error log.
--    On Linux, a backup to /dev/null fails (error 3634, "DiskChangeFileSize").
-- 3. Trace flag 3226 on, for the whole instance, until the next restart: a third backup
--    leaves no line. Failed backups are still logged. The backup file is deleted at the end.
USE master;
SET NOCOUNT ON;
GO
-- 1. Before, recycle, after.
EXEC sys.xp_enumerrorlogs 1;
EXEC sys.sp_cycle_errorlog;
EXEC msdb.dbo.sp_cycle_agent_errorlog;
EXEC sys.xp_enumerrorlogs 1;
EXEC sys.xp_enumerrorlogs 2;
EXEC sys.sp_readerrorlog 0, 1, N'Login failed';
EXEC sys.sp_readerrorlog 1, 1, N'Login failed';
GO
-- 2. Two backups, two lines.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_14';
BACKUP DATABASE DBA TO DISK = N'/var/opt/mssql/backup/module_14/DBA.bak' WITH COPY_ONLY, INIT;
BACKUP DATABASE DBA TO DISK = N'/var/opt/mssql/backup/module_14/DBA.bak' WITH COPY_ONLY, INIT;
EXEC sys.sp_readerrorlog 0, 1, N'Database backed up';
GO
-- 3. The trace flag, global (-1), then a third backup.
DBCC TRACEON (3226, -1);
DBCC TRACESTATUS (3226);
BACKUP DATABASE DBA TO DISK = N'/var/opt/mssql/backup/module_14/DBA.bak' WITH COPY_ONLY, INIT;
EXEC sys.sp_readerrorlog 0, 1, N'Database backed up';
-- The backup is still in msdb: the trace flag only silences the error log.
SELECT TOP (3) database_name, type, is_copy_only, backup_finish_date
FROM msdb.dbo.backupset
WHERE database_name = N'DBA' AND server_name = @@SERVERNAME
ORDER BY backup_set_id DESC;
GO
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_14/DBA.bak';
