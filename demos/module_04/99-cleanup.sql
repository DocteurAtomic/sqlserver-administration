-- Module 4, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It takes a second: it drops PachadataArchive, the database the module created, with its
-- files. PachadataTraining is restored by the next module's 00-setup.sql.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataArchive') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataArchive SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataArchive;
END;
GO
SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;
GO
