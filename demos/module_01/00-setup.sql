-- Module 1, setup. Runs on the lab, in one session, before the first clip of the module, on a
-- lab installed by setup/install.sh. It takes about five seconds.
-- Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170. The module
-- only reads the instance: it changes nothing, and has no 99-cleanup.sql.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE name = N'PachadataTraining';
