-- Module 6 exercise: start. Runs on your lab, in one session.
-- Restores a copy of the database, PachadataTraining_Ex06, which the exercise uses for the
-- three parts, and creates its exchange folder, /var/opt/mssql/exchange/exercise_06. The
-- exercise never writes in PachadataTraining. The snapshots that an earlier run left on
-- the copy are dropped first: a database cannot be restored while one exists.
USE master;
SET NOCOUNT ON;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP DATABASE ' + QUOTENAME(name) + N';'
FROM sys.databases
WHERE source_database_id = DB_ID(N'PachadataTraining_Ex06');
EXEC (@sql);
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex06';
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/exchange/exercise_06';
GO
-- The tables of the exercise.
USE PachadataTraining_Ex06;
SELECT N'Elearning.Progress' AS table_name, COUNT(*) AS row_count FROM Elearning.Progress
UNION ALL SELECT N'Enrollment.Answer', COUNT(*) FROM Enrollment.Answer
UNION ALL SELECT N'Enrollment.Payment', COUNT(*) FROM Enrollment.Payment;
SELECT COUNT(*) AS progress_before_2020
FROM Elearning.Progress
WHERE LastActivity < '20200101';
GO
