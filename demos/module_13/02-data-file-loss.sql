-- ci: skip (it deletes a file of the container between two parts)
-- Clip 13.2: the loss of the data file. Runs on the lab, after 00-setup.sql (and
-- 01-restore-phases.sql if you played it), with the clock job running. Do not run it in one
-- go: run part 1, delete the file from a terminal, then run the parts one by one.
-- Do this on the lab only: it deletes the data file of PachadataTraining, and gives the
-- database back without losing a committed transaction. The next module's 00-setup.sql
-- restores the database as delivered anyway.
USE master;
SET NOCOUNT ON;
GO
-- ========== Part 1: before the incident ==========
-- The ticks, and those that no backup contains yet: after the end of log 2.
DECLARE @last_log datetime = (SELECT MAX(last_valid_restore_time) FROM msdb.dbo.backupset
                              WHERE database_name = N'PachadataTraining' AND type = 'L'
                                AND server_name = @@SERVERNAME);
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick,
       SUM(CASE WHEN At > @last_log THEN 1 ELSE 0 END) AS ticks_after_last_log_backup
FROM PachadataTraining.dbo.RestoreClock;
SELECT name, physical_name FROM sys.master_files WHERE database_id = DB_ID(N'PachadataTraining');
GO

-- ========== In a terminal: delete the data file, and only it ==========
--   docker exec sqladmcourse rm /var/opt/mssql/data/PachadataTraining.mdf
--   (Podman: podman exec ...; on Windows, delete the .mdf in the Explorer)

-- ========== Part 2: the database still answers ==========
-- SQL Server keeps the file open: the deleted file is still readable and writable by the
-- engine, and the clock keeps ticking. Nothing happens until the file is closed.
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick FROM PachadataTraining.dbo.RestoreClock;
SELECT state_desc FROM sys.databases WHERE name = N'PachadataTraining';
GO

-- ========== Part 3: the file is closed ==========
-- The last tick, then the database offline: the engine closes its files. Then the attempt
-- to bring it online. Expected errors: 5120 (operating system error 2), 5181, 5069.
SELECT COUNT(*) AS ticks, MAX(At) AS last_tick FROM PachadataTraining.dbo.RestoreClock;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE PachadataTraining SET ONLINE;
GO
SELECT name, state_desc FROM sys.databases WHERE name = N'PachadataTraining';
GO
-- Expected error 945: the database cannot be opened.
SELECT COUNT(*) AS ticks FROM PachadataTraining.dbo.RestoreClock;
GO

-- ========== Part 4: the tail of the log, before anything else ==========
-- NO_TRUNCATE backs up the log of a database whose data file is lost.
BACKUP LOG PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_tail.trn'
    WITH NO_TRUNCATE, INIT, FORMAT;
GO
-- In the header: IsCopyOnly = 1, HasIncompleteMetaData = 1.
RESTORE HEADERONLY FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_tail.trn';
GO

-- ========== Part 5: the restore, in place ==========
-- Full, the last differential, the log backups after it, the tail. Log 1 is not needed:
-- the differential covers it. Neither MOVE nor REPLACE: the file is created again where it
-- was, and the tail of the log has been backed up.
RESTORE DATABASE PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_full.bak' WITH NORECOVERY;
RESTORE DATABASE PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_diff.bak' WITH NORECOVERY;
RESTORE LOG PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_log2.trn' WITH NORECOVERY;
RESTORE LOG PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_13/PachadataTraining_tail.trn' WITH RECOVERY;
GO

-- ========== Part 6: the check ==========
-- The clock started again as soon as the database came back. The gap separates the ticks of
-- before the incident from the new ones: the last tick before the gap is the last tick of
-- part 3. No committed transaction is lost. The wait lets the clock tick once more.
WAITFOR DELAY '00:00:12';
SELECT TOP (8) TickId, At,
       DATEDIFF(SECOND, LAG(At) OVER (ORDER BY TickId), At) AS gap_s
FROM PachadataTraining.dbo.RestoreClock
ORDER BY TickId DESC;
SELECT name, state_desc, recovery_model_desc FROM sys.databases WHERE name = N'PachadataTraining';
GO
-- The failures of the clock job while the database was away.
SELECT TOP (5) h.run_date, h.run_time, h.run_status, LEFT(h.message, 90) AS message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Module 13 - Clock' AND h.step_id = 1 AND h.run_status = 0
ORDER BY h.instance_id DESC;
GO
