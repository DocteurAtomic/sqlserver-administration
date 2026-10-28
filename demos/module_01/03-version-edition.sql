-- Clip 1.3: versions, editions and licenses. Runs on the lab, in one session, after
-- 00-setup.sql. Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. The version, the update level and the edition, one property at a time.
--    ProductLevel stays at RTM since 2017 (no more service packs): read ProductUpdateLevel.
--    ProductBuildType says GDR when a security update sits on top of the CU, NULL otherwise.
SELECT SERVERPROPERTY('ProductVersion')         AS product_version,
       SERVERPROPERTY('ProductLevel')           AS product_level,
       SERVERPROPERTY('ProductUpdateLevel')     AS update_level,
       SERVERPROPERTY('ProductBuildType')       AS build_type,
       SERVERPROPERTY('ProductUpdateReference') AS kb,
       SERVERPROPERTY('Edition')                AS edition,
       SERVERPROPERTY('EngineEdition')          AS engine_edition;

SELECT @@VERSION AS full_version;
GO
-- 2. What a database uses that depends on the edition, before moving it to another edition.
USE PachadataTraining;
SELECT feature_name FROM sys.dm_db_persisted_sku_features;
GO
-- 3. What the license lets the instance use: the message written at startup, and the
--    schedulers. VISIBLE OFFLINE schedulers would be processors the instance does not use.
USE master;
EXEC sys.xp_readerrorlog 0, 1, N'licensing';

SELECT i.cpu_count AS logical_processors_seen,
       (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE')  AS used,
       (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE OFFLINE') AS not_used
FROM sys.dm_os_sys_info AS i;
GO
-- 4. The identity card of the instance, in one row: what the team asked for.
SELECT @@SERVERNAME                                            AS server_name,
       CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion'))  AS build,
       CONVERT(nvarchar(10), SERVERPROPERTY('ProductUpdateLevel')) AS update_level,
       ISNULL(CONVERT(nvarchar(10), SERVERPROPERTY('ProductBuildType')), N'-') AS build_type,
       CONVERT(nvarchar(60), SERVERPROPERTY('Edition'))         AS edition,
       h.host_platform + N' ' + h.host_distribution + N' ' + h.host_release AS platform,
       (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE') AS schedulers,
       i.physical_memory_kb / 1024                              AS memory_mb,
       CONVERT(nvarchar(16), i.sqlserver_start_time, 120)       AS started_at
FROM sys.dm_os_sys_info AS i
CROSS JOIN sys.dm_os_host_info AS h;
GO
