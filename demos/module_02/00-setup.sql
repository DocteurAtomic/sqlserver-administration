-- Module 2, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Restores PachadataTraining as delivered, at level 170: clip 2.6 blocks one of its rows.
-- 2. Shows the configuration options the module sets, as the lab was installed: the
--    defaults of a SQL Server on Linux.
-- 99-cleanup.sql gives these options back the same values at the end.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'show advanced options', N'max server memory (MB)',
               N'max degree of parallelism', N'cost threshold for parallelism',
               N'optimize for ad hoc workloads', N'backup compression default',
               N'remote admin connections')
ORDER BY name;
GO
