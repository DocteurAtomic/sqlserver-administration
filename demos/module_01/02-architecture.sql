-- Clip 1.2: the architecture of an instance. Runs on the lab, in one session, after
-- 00-setup.sql. Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. The client side: my own connection, its transport and its version of TDS.
SELECT session_id, net_transport, protocol_type,
       CONVERT(varbinary(4), protocol_version) AS tds_version,
       encrypt_option, auth_scheme
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
GO
-- 2. SQLOS: the host it runs on, the processors and the memory it sees, its schedulers.
SELECT host_platform, host_distribution, host_release
FROM sys.dm_os_host_info;

SELECT cpu_count, scheduler_count, physical_memory_kb / 1024 AS physical_memory_mb,
       sql_memory_model_desc
FROM sys.dm_os_sys_info;

SELECT status, COUNT(*) AS schedulers
FROM sys.dm_os_schedulers
GROUP BY status
ORDER BY status;
GO
-- 3. The services of the instance, as the engine sees them.
SELECT servicename, startup_type_desc, status_desc, service_account
FROM sys.dm_server_services;
GO
-- 4. Instance, database, schema, object: the schemas of PachadataTraining and their tables,
--    read from master with three-part names.
SELECT s.name AS schema_name, USER_NAME(s.principal_id) AS schema_owner,
       COUNT(t.object_id) AS tables
FROM PachadataTraining.sys.schemas AS s
JOIN PachadataTraining.sys.tables AS t ON t.schema_id = s.schema_id
GROUP BY s.name, s.principal_id
ORDER BY tables DESC, s.name;

-- One query across two databases of the same instance: the course database and DBA.
SELECT N'PachadataTraining' AS database_name, COUNT(*) AS tables
FROM PachadataTraining.sys.tables
UNION ALL
SELECT N'DBA', COUNT(*)
FROM DBA.sys.tables;
GO
