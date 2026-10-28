-- Clip 3.4: the morning inventory of the instance, the request of the team. Runs on the lab,
-- in one session, from SSMS or from a terminal:
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -W \
--     < demos/module_03/04c-inventory.sql > inventory.txt; echo $?
-- Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. One row per database: state, recovery model, level, owner, collation, size.
--    collation_check says when a database does not have the collation of the instance,
--    hence of tempdb.
SELECT d.name AS database_name, d.state_desc, d.recovery_model_desc, d.compatibility_level,
       SUSER_SNAME(d.owner_sid) AS owner_name, d.collation_name,
       CASE WHEN d.collation_name <> CONVERT(sysname, SERVERPROPERTY('Collation'))
            THEN N'differs from tempdb' ELSE N'' END AS collation_check,
       SUM(CASE WHEN mf.type = 0 THEN mf.size END) / 128 AS data_mb,
       SUM(CASE WHEN mf.type = 1 THEN mf.size END) / 128 AS log_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name <> N'tempdb'
GROUP BY d.name, d.database_id, d.state_desc, d.recovery_model_desc, d.compatibility_level,
         d.owner_sid, d.collation_name
ORDER BY d.database_id;
GO
-- 2. One row per file: where it is, and how it grows.
SELECT DB_NAME(mf.database_id) AS database_name, mf.name AS logical_name, mf.type_desc,
       mf.physical_name, mf.size / 128 AS size_mb,
       CASE mf.is_percent_growth WHEN 1 THEN CONCAT(mf.growth, N' %')
            ELSE CONCAT(mf.growth / 128, N' MB') END AS growth
FROM sys.master_files AS mf
WHERE mf.database_id <> DB_ID(N'tempdb')
ORDER BY mf.database_id, mf.file_id;
GO
