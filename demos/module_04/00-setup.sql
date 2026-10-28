-- Module 4, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Drops PachadataArchive, the database the module creates, if an earlier run left it.
-- 2. Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170: the
--    module reads its Elearning.Activity table and never writes in it.
-- 99-cleanup.sql drops PachadataArchive at the end.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataArchive') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataArchive SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataArchive;
END;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
