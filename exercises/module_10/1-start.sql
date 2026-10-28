-- Module 10 exercise: starting point. Runs on your lab, in one session. A few seconds.
-- It never writes in PachadataTraining: it restores a copy, PachadataTraining_Ex10, and
-- creates in it the schema Planning, where the weekly list of the planning team goes.
-- The base stops in October 2026: "next week" is the week of Monday 2026-10-19.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex10';
GO
USE PachadataTraining_Ex10;
GO
CREATE SCHEMA Planning AUTHORIZATION dbo;
GO
-- The sessions of the week, as the job will have to list them.
SELECT COUNT(*) AS sessions_of_the_week,
       SUM(CASE WHEN TrainerId IS NULL THEN 1 ELSE 0 END) AS without_trainer
FROM Course.Session
WHERE StartDate >= '2026-10-19' AND StartDate < '2026-10-26'
  AND StatusCode <> 'CANCELED';
-- What the instance has before the exercise: the solution gives it back.
SELECT (SELECT COUNT(*) FROM msdb.dbo.sysjobs) AS agent_jobs,
       (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) AS mail_profiles,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations
        WHERE name = N'Database Mail XPs') AS database_mail_xps;
