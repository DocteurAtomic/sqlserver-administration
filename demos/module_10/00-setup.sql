-- Module 10, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Removes what an earlier run of the module may have left in msdb: its jobs, the
--    category Exports, its operator, its alerts. Ola Hallengren's ten jobs (setup/install.sh)
--    are not touched. Database Mail is removed by 99-cleanup.sql, not here.
-- 2. Restores PachadataTraining as delivered, at level 170.
-- 3. Creates the schema Export, where the nightly export of clip 10.1 writes.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. Leftovers of an earlier run.
DECLARE @job sysname;
DECLARE jobs CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM dbo.sysjobs
    WHERE name IN (N'Nightly invoice export', N'Linux subsystems', N'Log space watch',
                   N'Failing test');
OPEN jobs;
FETCH jobs INTO @job;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_delete_job @job_name = @job, @delete_unused_schedule = 1;
    FETCH jobs INTO @job;
END;
CLOSE jobs;
DEALLOCATE jobs;
IF EXISTS (SELECT * FROM dbo.syscategories WHERE name = N'Exports' AND category_class = 1)
    EXEC dbo.sp_delete_category @class = N'JOB', @name = N'Exports';
DECLARE @alert sysname;
WHILE EXISTS (SELECT * FROM dbo.sysalerts WHERE name LIKE N'PachaData - %')
BEGIN
    SELECT TOP (1) @alert = name FROM dbo.sysalerts WHERE name LIKE N'PachaData - %';
    EXEC dbo.sp_delete_alert @name = @alert;
END;
IF EXISTS (SELECT * FROM dbo.sysoperators WHERE name = N'DBA team')
    EXEC dbo.sp_delete_operator @name = N'DBA team';
GO
-- 2. The database as delivered.
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
-- 3. The schema of the exports.
CREATE SCHEMA Export AUTHORIZATION dbo;
GO
SELECT MAX(InvoiceDate) AS last_invoice_day,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobs) AS agent_jobs
FROM Enrollment.Invoice;
