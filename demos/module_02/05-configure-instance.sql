-- Clip 2.5: the settings after the installation. Played for the video on the throwaway
-- container sqladm-02, in one session.
-- ci: skip (it changes the configuration of the instance)
-- On your lab, 99-cleanup.sql gives the options back their values as the lab was installed.
-- The request: an instance that keeps memory for the system, does not send small queries
-- in parallel, compresses its backups and can always be reached by the DBA.
USE master;
SET NOCOUNT ON;
GO
-- 1. What the instance sees: the memory of the process and the nodes of SQLOS.
SELECT physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_mb,
       sql_memory_model_desc
FROM sys.dm_os_sys_info;
SELECT node_id, node_state_desc, memory_node_id, online_scheduler_count
FROM sys.dm_os_nodes
WHERE node_state_desc = N'ONLINE';
GO
-- 2. The advanced options become visible and changeable.
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
GO
-- 3. The six settings. Memory: the container gives the process 3,277 MB (80 % of 4 GB,
--    the rest is left to Linux), and the buffer pool must stay below it. The course keeps
--    a quarter of the process for what is not the buffer pool: 3,277 x 0.75 = 2,457 MB.
--    MAXDOP: the rule of Microsoft gives 8 for nodes of 11 schedulers, but the container
--    has a quota of two processors that SQL Server does not see: 2.
EXEC sys.sp_configure N'max server memory (MB)', 2457;
EXEC sys.sp_configure N'max degree of parallelism', 2;
EXEC sys.sp_configure N'cost threshold for parallelism', 50;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 1;
EXEC sys.sp_configure N'backup compression default', 1;
EXEC sys.sp_configure N'remote admin connections', 1;
GO
-- 4. Before RECONFIGURE: value has changed, value_in_use not yet.
SELECT name, value, value_in_use
FROM sys.configurations
WHERE value <> value_in_use
ORDER BY name;
GO
RECONFIGURE;
GO
-- 5. What the instance applies now. min server memory comes out too: 0 configured, 16 in
--    use, a difference that comes from the engine, not from a forgotten RECONFIGURE.
SELECT name, value, value_in_use, is_dynamic
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism', N'optimize for ad hoc workloads',
               N'backup compression default', N'remote admin connections')
   OR value <> value_in_use
ORDER BY name;
GO
