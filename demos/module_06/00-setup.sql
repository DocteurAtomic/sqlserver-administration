-- Module 6, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Drops what an earlier run of the module left: the snapshots of PachadataTraining (the
--    database cannot be restored while one exists) and the staging database PachadataStaging.
-- 2. Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170.
-- 3. Creates the exchange folder of the module, /var/opt/mssql/exchange. SQL Server creates
--    it, so it belongs to mssql, the account that reads it for BULK INSERT.
-- 99-cleanup.sql drops what the module adds.
USE master;
SET NOCOUNT ON;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP DATABASE ' + QUOTENAME(name) + N';'
FROM sys.databases
WHERE source_database_id = DB_ID(N'PachadataTraining');
EXEC (@sql);
IF DB_ID(N'PachadataStaging') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataStaging SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataStaging;
END;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/exchange';
GO
SELECT name, recovery_model_desc, compatibility_level, source_database_id
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
