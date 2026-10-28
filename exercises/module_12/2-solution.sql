-- Module 12 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- About a minute. It creates backups under /var/opt/mssql/backup/exercise_12, a certificate
-- in master, an Agent job, then deletes them all and drops PachadataTraining_Ex12 at the
-- end. T-SQL deletes neither folders nor the certificate files: they go with
--   docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_12
-- The request: the e-learning platform may lose one hour of progress at most (RPO), must be
-- back within thirty minutes (RTO), and its backup files are kept three days (72 hours).
USE master;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. The recovery model and the log.
-------------------------------------------------------------------------------------------
-- 1a. FULL. Until a first full backup, BACKUP LOG fails with error 4214 ("BACKUP LOG cannot
--     be performed because there is no current database backup"): last_log_backup_lsn is NULL.
ALTER DATABASE PachadataTraining_Ex12 SET RECOVERY FULL;
SELECT d.name, d.recovery_model_desc, rs.last_log_backup_lsn
FROM sys.databases AS d
JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
WHERE d.name = N'PachadataTraining_Ex12';
GO
-- 1b. The load, then a checkpoint: the log is truncated, as in SIMPLE.
USE PachadataTraining_Ex12;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds + 1;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds - 1;
CHECKPOINT;
SELECT N'no full backup yet' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb,
       (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME()) AS log_reuse_wait_desc
FROM sys.dm_db_log_space_usage;
GO
-------------------------------------------------------------------------------------------
-- Part 2. The strategy with DatabaseBackup: full, differential, log.
-------------------------------------------------------------------------------------------
-- 2a. The first full backup, ZSTD at level MEDIUM, kept 72 hours.
USE DBA;
DECLARE @first_log_id int = ISNULL((SELECT MAX(ID) FROM dbo.CommandLog), 0);
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining_Ex12', @Directory = N'/var/opt/mssql/backup/exercise_12',
    @BackupType = N'FULL', @Verify = N'Y', @Checksum = N'Y',
    @Compress = N'Y', @CompressionAlgorithm = N'ZSTD', @CompressionLevel = N'MEDIUM',
    @CleanupTime = 72, @LogToTable = N'Y';
-- 2b. The same load and checkpoint: the log now waits for its backup.
USE PachadataTraining_Ex12;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds + 1;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds - 1;
CHECKPOINT;
SELECT N'after the first full backup' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb,
       (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME()) AS log_reuse_wait_desc
FROM sys.dm_db_log_space_usage;
-- 2c. A differential, then a log backup.
USE DBA;
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining_Ex12', @Directory = N'/var/opt/mssql/backup/exercise_12',
    @BackupType = N'DIFF', @Verify = N'Y', @Checksum = N'Y',
    @Compress = N'Y', @CompressionAlgorithm = N'ZSTD', @CompressionLevel = N'MEDIUM',
    @CleanupTime = 72, @LogToTable = N'Y';
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining_Ex12', @Directory = N'/var/opt/mssql/backup/exercise_12',
    @BackupType = N'LOG', @Verify = N'Y', @Checksum = N'Y',
    @Compress = N'Y', @CompressionAlgorithm = N'ZSTD', @CompressionLevel = N'MEDIUM',
    @CleanupTime = 72, @LogToTable = N'Y';
SELECT N'after the log backup' AS moment,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM PachadataTraining_Ex12.sys.dm_db_log_space_usage;
-- 2d. What DatabaseBackup ran: a backup, a verification and a cleanup per call.
SELECT CommandType, ErrorNumber, LEFT(Command, 140) AS command
FROM dbo.CommandLog
WHERE ID > @first_log_id
ORDER BY ID;
GO
-- 2e. The chain in msdb: the differential's base is the full backup (its checkpoint LSN),
--     and the log backup starts where the full backup's log starts, the log not having been
--     backed up before.
SELECT b.type, b.is_copy_only,
       CAST(b.compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS file_mb,
       b.first_lsn, b.last_lsn, b.checkpoint_lsn, b.differential_base_lsn
FROM msdb.dbo.backupset AS b
WHERE b.database_name = N'PachadataTraining_Ex12' AND b.server_name = @@SERVERNAME
ORDER BY b.backup_set_id;
GO
-------------------------------------------------------------------------------------------
-- Part 3. A copy-only backup on two files.
-------------------------------------------------------------------------------------------
-- 3a. Two stripes, copy-only: the differentials keep their base.
USE DBA;
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining_Ex12', @Directory = N'/var/opt/mssql/backup/exercise_12',
    @BackupType = N'FULL', @CopyOnly = N'Y', @NumberOfFiles = 2,
    @Verify = N'Y', @Checksum = N'Y', @Compress = N'Y', @CompressionAlgorithm = N'ZSTD',
    @LogToTable = N'Y';
-- 3b. The media set has two families: both files are needed to restore.
DECLARE @file nvarchar(4000) = (
    SELECT TOP (1) f.physical_device_name
    FROM msdb.dbo.backupset AS b
    JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
    WHERE b.database_name = N'PachadataTraining_Ex12' AND b.is_copy_only = 1
    ORDER BY b.backup_set_id DESC, f.family_sequence_number);
SELECT @file AS first_file;
RESTORE LABELONLY FROM DISK = @file;
GO
-------------------------------------------------------------------------------------------
-- Part 4. An encrypted backup.
-------------------------------------------------------------------------------------------
-- 4a. The master key of master if it is missing, the certificate, and its backup first.
USE master;
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Master-Key-Ex12!lab';
CREATE CERTIFICATE ExerciseCert12
    WITH SUBJECT = N'Backup encryption of exercise 12', EXPIRY_DATE = '20291231';
BACKUP CERTIFICATE ExerciseCert12
    TO FILE = N'/var/opt/mssql/backup/exercise_12/ExerciseCert12.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/exercise_12/ExerciseCert12.pvk',
                      ENCRYPTION BY PASSWORD = N'Cert-Ex12-2026!lab');
GO
-- 4b. DatabaseBackup encrypts with @Encrypt, @EncryptionAlgorithm, @ServerCertificate.
USE DBA;
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining_Ex12', @Directory = N'/var/opt/mssql/backup/exercise_12',
    @BackupType = N'FULL', @CopyOnly = N'Y', @Verify = N'Y', @Checksum = N'Y',
    @Compress = N'Y', @CompressionAlgorithm = N'ZSTD',
    @Encrypt = N'Y', @EncryptionAlgorithm = N'AES_256', @ServerCertificate = N'ExerciseCert12',
    @LogToTable = N'Y';
SELECT TOP (1) b.key_algorithm, b.encryptor_type, b.compression_algorithm, b.is_copy_only
FROM msdb.dbo.backupset AS b
WHERE b.database_name = N'PachadataTraining_Ex12'
ORDER BY b.backup_set_id DESC;
SELECT name, expiry_date, pvt_key_last_backup_date
FROM master.sys.certificates WHERE name = N'ExerciseCert12';
GO
-------------------------------------------------------------------------------------------
-- Part 5. The log backup scheduled every hour, and the proof.
-------------------------------------------------------------------------------------------
-- 5a. A job of one T-SQL step, run in DBA, scheduled every hour (RPO of one hour).
USE msdb;
EXEC dbo.sp_add_job @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG';
EXEC dbo.sp_add_jobstep
    @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG', @step_name = N'DatabaseBackup LOG',
    @subsystem = N'TSQL', @database_name = N'DBA',
    @command = N'EXECUTE dbo.DatabaseBackup @Databases = N''PachadataTraining_Ex12'',
@Directory = N''/var/opt/mssql/backup/exercise_12'', @BackupType = N''LOG'',
@Verify = N''Y'', @Checksum = N''Y'', @Compress = N''Y'', @CompressionAlgorithm = N''ZSTD'',
@CompressionLevel = N''MEDIUM'', @CleanupTime = 72, @LogToTable = N''Y''';
EXEC dbo.sp_add_jobschedule
    @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG', @name = N'Every hour',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 8, @freq_subday_interval = 1;
EXEC dbo.sp_add_jobserver @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG';
GO
-- 5b. Started by hand; the history once it has finished.
EXEC msdb.dbo.sp_start_job @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG';
DECLARE @wait int = 0;
WHILE @wait < 30 AND NOT EXISTS (
    SELECT * FROM msdb.dbo.sysjobhistory AS h
    JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
    WHERE j.name = N'Exercise 12 - PachadataTraining_Ex12 - LOG' AND h.step_id = 0)
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @wait += 1;
END;
SELECT h.step_id, h.run_status, LEFT(h.message, 60) AS message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Exercise 12 - PachadataTraining_Ex12 - LOG'
ORDER BY h.instance_id;
-- 5c. The proof: FULL, a log backup less than an hour old, a job every hour.
SELECT d.recovery_model_desc,
       DATEDIFF(minute, MAX(b.backup_finish_date), GETDATE()) AS minutes_since_log_backup,
       (SELECT sc.freq_subday_interval FROM msdb.dbo.sysschedules AS sc
        WHERE sc.name = N'Every hour') AS every_n_hours
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
       ON b.database_name = d.name AND b.type = 'L' AND b.server_name = @@SERVERNAME
WHERE d.name = N'PachadataTraining_Ex12'
GROUP BY d.recovery_model_desc;
GO
-------------------------------------------------------------------------------------------
-- Cleanup: the job, the backup files (before the certificate: deleting an encrypted backup
-- reads its header), the history, the certificate, the master key if nothing else uses it,
-- the database.
-------------------------------------------------------------------------------------------
USE msdb;
EXEC dbo.sp_delete_job @job_name = N'Exercise 12 - PachadataTraining_Ex12 - LOG',
     @delete_unused_schedule = 1;
GO
DECLARE @root nvarchar(400) = N'/var/opt/mssql/backup/exercise_12/'
    + CAST(SERVERPROPERTY('MachineName') AS nvarchar(128)) + N'/PachadataTraining_Ex12/';
DECLARE @path nvarchar(400);
DECLARE folders CURSOR LOCAL FAST_FORWARD FOR
    SELECT @root + v.folder FROM (VALUES (N'FULL'), (N'DIFF'), (N'LOG'), (N'FULL_COPY_ONLY')) AS v (folder);
OPEN folders;
FETCH NEXT FROM folders INTO @path;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.sys.xp_delete_file 0, @path, N'bak', N'2100-01-01', 0;
    EXEC master.sys.xp_delete_file 0, @path, N'trn', N'2100-01-01', 0;
    FETCH NEXT FROM folders INTO @path;
END;
CLOSE folders;
DEALLOCATE folders;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex12';
GO
USE master;
DROP CERTIFICATE ExerciseCert12;
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
ALTER DATABASE PachadataTraining_Ex12 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex12;
GO
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/exercise_12', 0, 1;
GO
