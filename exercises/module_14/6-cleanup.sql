-- Module 14 exercise: cleanup. Runs on your lab, in one session, at the very end of the
-- exercise. A second. It drops the copy PachadataTraining_Ex14, the job and the history
-- table of part 2. sp_WhoIsActive stays in DBA until demos/module_14/99-cleanup.sql.
USE master;
SET NOCOUNT ON;
GO
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Exercise 14 - Activity history')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Exercise 14 - Activity history';
IF OBJECT_ID(N'DBA.dbo.ActivityHistory') IS NOT NULL
    DROP TABLE DBA.dbo.ActivityHistory;
IF DB_ID(N'PachadataTraining_Ex14') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataTraining_Ex14 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataTraining_Ex14;
END;
GO
SELECT DB_ID(N'PachadataTraining_Ex14') AS copy_left,
       OBJECT_ID(N'DBA.dbo.ActivityHistory') AS table_left,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'Exercise 14%') AS jobs_left;
