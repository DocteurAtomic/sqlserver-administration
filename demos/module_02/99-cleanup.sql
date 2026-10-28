-- Module 2, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It takes a second: it gives the options that 05-configure-instance.sql and the exercise
-- change their values as the lab was installed, then hides the advanced options again.
-- The scripts 03, 04 and 06 clean up after themselves (mssql.conf, port, transaction).
USE master;
SET NOCOUNT ON;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
GO
EXEC sys.sp_configure N'max server memory (MB)', 2147483647;
EXEC sys.sp_configure N'max degree of parallelism', 0;
EXEC sys.sp_configure N'cost threshold for parallelism', 5;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 0;
EXEC sys.sp_configure N'backup compression default', 0;
EXEC sys.sp_configure N'remote admin connections', 0;
RECONFIGURE;
GO
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
GO
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'show advanced options', N'max server memory (MB)',
               N'max degree of parallelism', N'cost threshold for parallelism',
               N'optimize for ad hoc workloads', N'backup compression default',
               N'remote admin connections')
   OR value <> value_in_use
ORDER BY name;
GO
