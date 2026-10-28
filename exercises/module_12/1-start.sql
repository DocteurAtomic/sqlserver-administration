-- Module 12 exercise: start. Runs on your lab, in one session, after
-- ./setup/install-ola.sh (DatabaseBackup in the database DBA).
-- Restores a copy of the database, PachadataTraining_Ex12, which stands for the e-learning
-- platform, and creates the root folder of its backups. The exercise never writes in
-- PachadataTraining. The solution deletes what it creates, the copy included.
USE master;
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'DBA.dbo.DatabaseBackup') IS NULL
    RAISERROR (N'DBA.dbo.DatabaseBackup is missing: run ./setup/install-ola.sh first.', 16, 1);
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex12';
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_12';
GO
-- The database, and the table of the load: the progress of each enrollment in each module.
SELECT d.name, d.recovery_model_desc, rs.last_log_backup_lsn, d.log_reuse_wait_desc
FROM sys.databases AS d
JOIN sys.database_recovery_status AS rs ON rs.database_id = d.database_id
WHERE d.name = N'PachadataTraining_Ex12';
SELECT COUNT(*) AS progress_rows FROM PachadataTraining_Ex12.Elearning.Progress;
GO
