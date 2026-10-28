-- ci: skip (it deletes a file of the container between two parts)
-- Module 13 exercise: solution, part 4. Runs on your lab, after 2-solution.sql (or after
-- your own repair). Do not run it in one go: run part A, delete the file from a terminal,
-- then run part B. The repair of part 3 is in no backup yet: only the tail of the log
-- keeps it. At the end, the script drops PachadataTraining_Ex13, its backup files and their
-- history.
USE master;
SET NOCOUNT ON;
GO
-- ========== Part A: the rates as repaired, then the database offline ==========
SELECT COUNT(*) AS engagements, AVG(DailyRate) AS avg_rate, MAX(DailyRate) AS max_rate
FROM PachadataTraining_Ex13.Trainer.Engagement;
ALTER DATABASE PachadataTraining_Ex13 SET OFFLINE WITH ROLLBACK IMMEDIATE;
GO

-- ========== In a terminal: delete the data file of the copy, and only it ==========
--   docker exec sqladmcourse rm /var/opt/mssql/data/PachadataTraining_Ex13.mdf

-- ========== Part B: the failure, the tail, the restore, the check ==========
-- Expected errors 5120, 5181 and 5069; the database stays in RECOVERY_PENDING.
ALTER DATABASE PachadataTraining_Ex13 SET ONLINE;
GO
SELECT name, state_desc FROM sys.databases WHERE name = N'PachadataTraining_Ex13';
BACKUP LOG PachadataTraining_Ex13
    TO DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_tail.trn' WITH NO_TRUNCATE, INIT, FORMAT;
GO
-- In place, without MOVE nor REPLACE: the full backup, the three log backups, the tail.
RESTORE DATABASE PachadataTraining_Ex13
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_full.bak' WITH NORECOVERY;
RESTORE LOG PachadataTraining_Ex13
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_log1.trn' WITH NORECOVERY;
RESTORE LOG PachadataTraining_Ex13
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_log2.trn' WITH NORECOVERY;
RESTORE LOG PachadataTraining_Ex13
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_log3.trn' WITH NORECOVERY;
RESTORE LOG PachadataTraining_Ex13
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_tail.trn' WITH RECOVERY;
GO
-- The same rates as in part A: the repair came back with the tail.
SELECT COUNT(*) AS engagements, AVG(DailyRate) AS avg_rate, MAX(DailyRate) AS max_rate,
       SUM(CASE WHEN InvoiceNumber = 'EX13-NEW' THEN 1 ELSE 0 END) AS new_engagement_kept
FROM PachadataTraining_Ex13.Trainer.Engagement;
GO

-- ========== Cleanup ==========
ALTER DATABASE PachadataTraining_Ex13 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex13;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'trn', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13';
GO
-- The empty folder goes with: docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_13
