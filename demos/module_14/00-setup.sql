-- Module 14, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Removes what an earlier run of the module may have left on the instance: the event
--    session LongQueries, the server trigger DatabaseChanges, the table
--    DBA.dbo.DatabaseChangeLog, and the job of 01b-events.sh. sp_WhoIsActive stays if it
--    is there: 02a-install-whoisactive.sh installs it again anyway. The trace flag 3226 is
--    left as it is: 99-cleanup.sql turns it off.
-- 2. Restores PachadataTraining as delivered (RCSI on, Query Store on), at level 170.
-- 99-cleanup.sql removes what the module adds to the instance, sp_WhoIsActive included.
USE master;
SET NOCOUNT ON;
GO
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = N'LongQueries')
    DROP EVENT SESSION LongQueries ON SERVER;
IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'DatabaseChanges')
    DROP TRIGGER DatabaseChanges ON ALL SERVER;
IF OBJECT_ID(N'DBA.dbo.DatabaseChangeLog') IS NOT NULL
    DROP TABLE DBA.dbo.DatabaseChangeLog;
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Module 14 - Nightly export')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Module 14 - Nightly export';
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, is_read_committed_snapshot_on AS rcsi,
       is_query_store_on AS query_store, compatibility_level
FROM sys.databases
WHERE name = N'PachadataTraining';
