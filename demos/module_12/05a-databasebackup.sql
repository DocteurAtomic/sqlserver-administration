-- Clip 12.5: DatabaseBackup, from Ola Hallengren's scripts. Runs on the lab, in one session,
-- after 02-backup-chain.sql (it also runs alone: part 1 puts the database in FULL).
-- The procedure is in the database DBA, installed by ./setup/install-ola.sh.
-- Its backups go to /var/opt/mssql/backup/module_12/ola.
USE master;
SET NOCOUNT ON;
ALTER DATABASE PachadataTraining SET RECOVERY FULL;
GO
-- 1. The root folder must exist: DatabaseBackup creates the folders below it, not the root.
EXECUTE master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_12/ola';
GO
-- 2. A full backup, then a log backup, with the same options.
USE DBA;
DECLARE @first_log_id int = ISNULL((SELECT MAX(ID) FROM dbo.CommandLog), 0);
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining',
    @Directory = N'/var/opt/mssql/backup/module_12/ola',
    @BackupType = N'FULL',
    @Verify = N'Y',
    @Checksum = N'Y',
    @Compress = N'Y',
    @CompressionAlgorithm = N'ZSTD',
    @CleanupTime = 336,
    @LogToTable = N'Y';
EXECUTE dbo.DatabaseBackup
    @Databases = N'PachadataTraining',
    @Directory = N'/var/opt/mssql/backup/module_12/ola',
    @BackupType = N'LOG',
    @Verify = N'Y',
    @Checksum = N'Y',
    @Compress = N'Y',
    @CompressionAlgorithm = N'ZSTD',
    @CleanupTime = 336,
    @LogToTable = N'Y';

-- 3. What the procedure ran: three commands per call.
SELECT CommandType, DatabaseName, ErrorNumber,
       DATEDIFF(ms, StartTime, EndTime) AS ms, Command
FROM dbo.CommandLog
WHERE ID > @first_log_id
ORDER BY ID;
GO
-- 4. The folders and files it created.
EXECUTE master.sys.xp_dirtree N'/var/opt/mssql/backup/module_12/ola', 0, 1;
GO
