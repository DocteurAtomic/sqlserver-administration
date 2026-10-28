-- Module 3, setup. Runs on the lab, in one session, before the first clip of the module, on a
-- lab installed by setup/install.sh. It takes about five seconds.
-- Restores PachadataTraining as delivered (recovery model SIMPLE, collation French_CI_AS), at
-- level 170. The clips read the instance and the database; the two scripts that change the
-- instance (model and tempdb) run on a throwaway container, see 02-throwaway-container.sh.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, compatibility_level, collation_name
FROM sys.databases
WHERE name = N'PachadataTraining';
