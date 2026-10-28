-- Clip 15.1: is this instance part of a high availability architecture? Runs on the lab, in one
-- session, after 00-setup.sql. Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. The instance level: availability groups enabled, failover cluster instance, edition.
SELECT SERVERPROPERTY('IsHadrEnabled')     AS is_hadr_enabled,
       SERVERPROPERTY('HadrManagerStatus') AS hadr_manager_status,
       SERVERPROPERTY('IsClustered')       AS is_clustered,
       SERVERPROPERTY('EngineEdition')     AS engine_edition,
       SERVERPROPERTY('Edition')           AS edition;
GO
-- 2. What exists on the instance: availability groups, log shipping configurations, mirrored
--    databases.
SELECT (SELECT COUNT(*) FROM sys.availability_groups) AS availability_groups,
       (SELECT COUNT(*) FROM msdb.dbo.log_shipping_primary_databases) AS log_shipping_primaries,
       (SELECT COUNT(*) FROM msdb.dbo.log_shipping_secondary_databases) AS log_shipping_secondaries,
       (SELECT COUNT(*) FROM sys.database_mirroring
        WHERE mirroring_guid IS NOT NULL) AS mirrored_databases;
GO
-- 3. Database by database: recovery model, availability group and its state, mirroring role,
--    log shipping role.
SELECT d.name,
       d.recovery_model_desc,
       ag.name AS availability_group,
       drs.synchronization_state_desc,
       m.mirroring_role_desc,
       IIF(lsp.primary_database IS NOT NULL, N'primary',
           IIF(lss.secondary_database IS NOT NULL, N'secondary', NULL)) AS log_shipping
FROM sys.databases AS d
LEFT JOIN sys.dm_hadr_database_replica_states AS drs
       ON drs.database_id = d.database_id AND drs.is_local = 1
LEFT JOIN sys.availability_groups AS ag ON ag.group_id = drs.group_id
LEFT JOIN sys.database_mirroring AS m
       ON m.database_id = d.database_id AND m.mirroring_guid IS NOT NULL
LEFT JOIN msdb.dbo.log_shipping_primary_databases AS lsp
       ON lsp.primary_database = d.name
LEFT JOIN msdb.dbo.log_shipping_secondary_databases AS lss
       ON lss.secondary_database = d.name
WHERE d.database_id > 4
ORDER BY d.name;
GO
-- 4. The test an Agent job step runs first on an availability group: 1 on the primary, 0 on a
--    secondary, NULL when the database belongs to no availability group.
SELECT sys.fn_hadr_is_primary_replica(N'PachadataTraining') AS is_primary_replica;
GO
