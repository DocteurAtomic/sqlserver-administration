-- Clip 3.2: the system databases. Runs on the lab, in one session, after 00-setup.sql.
-- Reads the instance, then creates a database with no option at all to see what it takes
-- from model, and drops it. A few seconds.
USE master;
SET NOCOUNT ON;
GO
-- 1. The four system databases that sys.databases shows. The create date of tempdb is the
--    last start of the instance: tempdb is created again at every start.
SELECT database_id, name, recovery_model_desc, compatibility_level, collation_name, create_date
FROM sys.databases
WHERE database_id <= 4
ORDER BY database_id;
GO
-- 2. The fifth one, Resource: no row in sys.databases, no name for its id 32767, no file in
--    sys.master_files. It follows the update level of the instance, and holds the code of
--    the sys objects that every database shows.
SELECT DB_NAME(32767)                                AS resource_name,
       SERVERPROPERTY('ResourceVersion')             AS resource_version,
       SERVERPROPERTY('ResourceLastUpdateDateTime')  AS resource_updated,
       SERVERPROPERTY('ProductVersion')              AS product_version,
       (SELECT COUNT(*) FROM sys.master_files WHERE database_id = 32767) AS resource_files,
       (SELECT COUNT(*) FROM sys.system_objects)     AS system_objects;
GO
-- 3. The files of the system databases, as master knows them. For tempdb, sys.master_files
--    gives the size it is created with at startup; tempdb.sys.database_files the size now.
SELECT DB_NAME(mf.database_id) AS database_name, mf.name AS logical_name, mf.type_desc,
       mf.physical_name, mf.size / 128 AS size_mb,
       CASE mf.is_percent_growth WHEN 1 THEN CONCAT(mf.growth, N' %')
            ELSE CONCAT(mf.growth / 128, N' MB') END AS growth
FROM sys.master_files AS mf
WHERE mf.database_id <= 4
ORDER BY mf.database_id, mf.file_id;

SELECT N'tempdb' AS database_name,
       SUM(CASE WHEN type_desc = N'ROWS' THEN 1 ELSE 0 END) AS data_files,
       (SELECT SUM(size) / 128 FROM sys.master_files
        WHERE database_id = 2) AS startup_size_mb,
       SUM(size) / 128 AS current_size_mb
FROM tempdb.sys.database_files;
GO
-- 4. model is the template of CREATE DATABASE. A database created with no option takes its
--    recovery model, its file sizes and growth, and its Query Store setting.
IF DB_ID(N'Module03_NoOption') IS NOT NULL
    DROP DATABASE Module03_NoOption;
GO
CREATE DATABASE Module03_NoOption;
GO
SELECT d.name, d.recovery_model_desc, d.compatibility_level, d.is_query_store_on,
       d.collation_name,
       (SELECT mf.size / 128 FROM sys.master_files AS mf
        WHERE mf.database_id = d.database_id AND mf.type = 0) AS data_mb,
       (SELECT mf.growth / 128 FROM sys.master_files AS mf
        WHERE mf.database_id = d.database_id AND mf.type = 0) AS data_growth_mb,
       (SELECT mf.size / 128 FROM sys.master_files AS mf
        WHERE mf.database_id = d.database_id AND mf.type = 1) AS log_mb
FROM sys.databases AS d
WHERE d.name IN (N'model', N'Module03_NoOption')
ORDER BY d.database_id;
GO
DROP DATABASE Module03_NoOption;
GO
