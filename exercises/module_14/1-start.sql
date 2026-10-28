-- Module 14 exercise: starting point. Runs on your lab, in one session. A few seconds.
-- It never writes in PachadataTraining: it restores a copy, PachadataTraining_Ex14, and
-- prepares in it what the exercise needs.
-- 1. The copy, with READ_COMMITTED_SNAPSHOT turned off: on this copy, a reader waits for a
--    writer, as on a database that never turned RCSI on.
-- 2. The developer of the planning tool, PlanningDev, a user without login who may change
--    the structure of the database (db_ddladmin) and nothing else.
-- 3. A message in the error log, written on purpose, for part 1.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex14';
GO
ALTER DATABASE PachadataTraining_Ex14 SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
GO
USE PachadataTraining_Ex14;
GO
CREATE USER PlanningDev WITHOUT LOGIN;
ALTER ROLE db_ddladmin ADD MEMBER PlanningDev;
GO
RAISERROR (N'Exercise 14: planning tool release 3.2 deployed', 10, 1) WITH LOG;
GO
SELECT name, is_read_committed_snapshot_on AS rcsi, is_query_store_on AS query_store
FROM sys.databases
WHERE name = N'PachadataTraining_Ex14';
