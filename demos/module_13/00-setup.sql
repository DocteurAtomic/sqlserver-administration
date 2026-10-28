-- ci: skip (it waits two minutes and creates an Agent job)
-- Module 13, setup. Runs on the lab, in one session, before the first clip of the module,
-- with SQL Server Agent running. It takes about two minutes.
-- 1. Creates the folder of the module's backups, /var/opt/mssql/backup/module_13, and
--    deletes the backup files and the backup history that an earlier run left there.
-- 2. Restores PachadataTraining as delivered, at level 170, and puts it in FULL.
-- 3. Creates the clock: the table dbo.RestoreClock, and the Agent job "Module 13 - Clock",
--    which inserts one row every 10 seconds, the shortest interval of the Agent. Every
--    restore of the module is checked against the last tick of the clock.
-- 4. Takes the chain the incidents need, 30 seconds apart: full, log 1, differential, log 2.
-- 99-cleanup.sql removes the job, the backup files and the history.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_13';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_13', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_13', N'trn', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
-- 2. The database, in FULL.
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Module 13 - Clock')
    EXEC msdb.dbo.sp_update_job @job_name = N'Module 13 - Clock', @enabled = 0;
EXEC master.dbo.reset_training @db = N'PachadataTraining';
ALTER DATABASE PachadataTraining SET RECOVERY FULL;
GO
-- 3. The clock.
USE PachadataTraining;
CREATE TABLE dbo.RestoreClock (
    TickId int IDENTITY PRIMARY KEY,
    At     datetime2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
USE msdb;
IF EXISTS (SELECT * FROM dbo.sysjobs WHERE name = N'Module 13 - Clock')
    EXEC dbo.sp_delete_job @job_name = N'Module 13 - Clock';
EXEC dbo.sp_add_job @job_name = N'Module 13 - Clock';
EXEC dbo.sp_add_jobstep @job_name = N'Module 13 - Clock', @step_name = N'Tick',
     @subsystem = N'TSQL', @database_name = N'PachadataTraining',
     @command = N'INSERT INTO dbo.RestoreClock DEFAULT VALUES;';
-- freq_subday_type 2: every n seconds.
EXEC dbo.sp_add_jobschedule @job_name = N'Module 13 - Clock', @name = N'Module 13 - Every 10 seconds',
     @freq_type = 4, @freq_interval = 1, @freq_subday_type = 2, @freq_subday_interval = 10;
EXEC dbo.sp_add_jobserver @job_name = N'Module 13 - Clock';
GO
-- 4. The chain.
USE master;
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak'
    WITH INIT, FORMAT, CHECKSUM;
WAITFOR DELAY '00:00:30';
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log1.trn'
    WITH INIT, FORMAT, CHECKSUM;
WAITFOR DELAY '00:00:30';
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_diff.bak'
    WITH DIFFERENTIAL, INIT, FORMAT, CHECKSUM;
WAITFOR DELAY '00:00:30';
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log2.trn'
    WITH INIT, FORMAT, CHECKSUM;
GO
-- The chain, as msdb records it, and the clock.
SELECT b.type, b.backup_start_date, b.last_valid_restore_time,
       RIGHT(f.physical_device_name, CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1) AS file_name
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining' AND b.server_name = @@SERVERNAME
ORDER BY b.backup_set_id;
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick FROM PachadataTraining.dbo.RestoreClock;
GO
