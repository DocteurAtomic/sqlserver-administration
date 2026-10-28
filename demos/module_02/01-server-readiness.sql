-- Clip 2.1: what the preparation of the server left. Runs on the lab, in one session.
-- It reads the instance, then creates and drops a database IfiDemo (a few seconds).
-- The trace flags 3004 and 3605 are set for this session only, and removed at the end.
USE master;
SET NOCOUNT ON;
GO
-- 1. The services, their account, and Instant File Initialization.
SELECT servicename, startup_type_desc, status_desc, service_account,
       instant_file_initialization_enabled
FROM sys.dm_server_services;
GO
-- 2. Lock Pages in Memory: CONVENTIONAL without the privilege, LOCK_PAGES with it.
SELECT physical_memory_kb / 1024 AS physical_memory_mb, sql_memory_model_desc
FROM sys.dm_os_sys_info;
GO
-- 3. Where the files go by default, and where the files of each database are.
SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS default_data,
       SERVERPROPERTY('InstanceDefaultLogPath') AS default_log,
       SERVERPROPERTY('InstanceDefaultBackupPath') AS default_backup;
SELECT DB_NAME(database_id) AS database_name, type_desc,
       LEFT(physical_name, LEN(physical_name) - CHARINDEX(N'/', REVERSE(physical_name)) + 1) AS folder,
       COUNT(*) AS files
FROM sys.master_files
GROUP BY database_id, type_desc,
         LEFT(physical_name, LEN(physical_name) - CHARINDEX(N'/', REVERSE(physical_name)) + 1)
ORDER BY database_id, type_desc;
GO
-- 4. IFI at work. Trace flag 3004 writes every zeroing of a file, 3605 sends it to the
--    error log. A data file of 1 GB and a log of 256 MB.
DBCC TRACEON (3004, 3605) WITH NO_INFOMSGS;
IF DB_ID(N'IfiDemo') IS NOT NULL DROP DATABASE IfiDemo;
CREATE DATABASE IfiDemo
    ON (NAME = IfiDemo, FILENAME = N'/var/opt/mssql/data/IfiDemo.mdf', SIZE = 1024MB)
    LOG ON (NAME = IfiDemo_log, FILENAME = N'/var/opt/mssql/data/IfiDemo_log.ldf', SIZE = 256MB);
DBCC TRACEOFF (3004, 3605) WITH NO_INFOMSGS;
GO
EXEC sys.xp_readerrorlog 0, 1, N'Zeroing', N'IfiDemo';
DROP DATABASE IfiDemo;
GO
