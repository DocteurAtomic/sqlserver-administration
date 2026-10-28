-- Clip 4.3: the database options. Runs on the lab, in one session, after
-- 02-transaction-log.sql. It takes a few seconds.
-- Part 2 gives PachadataArchive the settings of a badly kept database, to see what they
-- do; part 4 corrects them.
USE master;
SET NOCOUNT ON;
GO
-- 1. The options that matter, for every user database, and the collation of the instance.
SELECT SERVERPROPERTY('Collation') AS instance_collation;
SELECT name, SUSER_SNAME(owner_sid) AS owner_name, recovery_model_desc,
       is_auto_close_on, is_auto_shrink_on, page_verify_option_desc,
       is_auto_create_stats_on, is_auto_update_stats_on, collation_name
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
GO
-- 2. The settings found on old or migrated databases.
ALTER DATABASE PachadataArchive
    SET AUTO_CLOSE ON, AUTO_SHRINK ON, PAGE_VERIFY TORN_PAGE_DETECTION,
        AUTO_CREATE_STATISTICS OFF;
GO
-- No session uses the database any more: AUTO_CLOSE closes it, in the background, within a
-- few seconds. Closed, its collation reads NULL.
DECLARE @waited int = 0;
WHILE (SELECT collation_name FROM sys.databases WHERE name = N'PachadataArchive') IS NOT NULL
      AND @waited < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @waited += 1;
END;
SELECT @waited AS seconds_waited;
SELECT name, is_auto_close_on, collation_name,
       DATABASEPROPERTYEX(name, 'Collation') AS collation_property,
       DATABASEPROPERTYEX(name, 'IsAutoClose') AS is_auto_close
FROM sys.databases
WHERE name = N'PachadataArchive';
GO
-- 3. Generate the corrections, one statement per database, only the options that differ.
--    Read the text before running it.
SELECT d.name,
       N'ALTER DATABASE ' + QUOTENAME(d.name) + N' SET '
       + STUFF(  CASE WHEN d.is_auto_close_on = 1 THEN N', AUTO_CLOSE OFF' ELSE N'' END
               + CASE WHEN d.is_auto_shrink_on = 1 THEN N', AUTO_SHRINK OFF' ELSE N'' END
               + CASE WHEN d.page_verify_option <> 2 THEN N', PAGE_VERIFY CHECKSUM' ELSE N'' END
               + CASE WHEN d.is_auto_create_stats_on = 0 THEN N', AUTO_CREATE_STATISTICS ON' ELSE N'' END
               + CASE WHEN d.is_auto_update_stats_on = 0 THEN N', AUTO_UPDATE_STATISTICS ON' ELSE N'' END,
               1, 2, N'') + N';' AS correction
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.source_database_id IS NULL      -- not the database snapshots
  AND (d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1 OR d.page_verify_option <> 2
       OR d.is_auto_create_stats_on = 0 OR d.is_auto_update_stats_on = 0);
GO
-- 4. The correction, and an owner that will not disappear.
ALTER DATABASE PachadataArchive
    SET AUTO_CLOSE OFF, AUTO_SHRINK OFF, PAGE_VERIFY CHECKSUM, AUTO_CREATE_STATISTICS ON;
ALTER AUTHORIZATION ON DATABASE::PachadataArchive TO sa;
GO
SELECT name, SUSER_SNAME(owner_sid) AS owner_name, is_auto_close_on, is_auto_shrink_on,
       page_verify_option_desc, is_auto_create_stats_on, is_auto_update_stats_on,
       collation_name
FROM sys.databases
WHERE name = N'PachadataArchive';
GO
