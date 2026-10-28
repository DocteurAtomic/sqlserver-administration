-- Module 3 exercise: start. Runs on your lab, in one session, in about five seconds.
-- Restores a copy of the course database, PachadataTraining_Ex03, for the collation part.
-- The exercise never writes in PachadataTraining. It creates a database and backs up the
-- three system databases that are backed up; the solution deletes all of it at the end.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex03';
GO
IF DB_ID(N'Exercise03_Default') IS NOT NULL
    DROP DATABASE Exercise03_Default;
GO
SELECT name, collation_name FROM sys.databases WHERE name = N'PachadataTraining_Ex03';
GO
