-- Module 14 exercise: solution of parts 2 and 3. Read it after searching. Each block runs at
-- its moment: select it, then F5.
-- ci: skip (it needs the windows A, B and C, then 4-big-transaction.sql)
--   A. while windows A, B and C wait: the chain by the DMVs, then by sp_WhoIsActive;
--   B. still during the chain: a history table of the activity, fed every minute by a job
--      of the Agent, with its purge;
--   C. after ROLLBACK in window A, while 4-big-transaction.sql waits: look at the
--      transaction, kill it, follow the rollback.
-- Prerequisite: sp_WhoIsActive in DBA (demos/module_14/02a-install-whoisactive.sh).

-- ===== A. The chain ====================================================================
USE PachadataTraining_Ex14;
SET NOCOUNT ON;
GO
-- Who waits, behind whom, on what. Without RCSI, window B waits too (LCK_M_S); window C
-- names window B, not window A: the requests for a lock are served in order of arrival.
SELECT r.session_id, r.blocking_session_id, r.wait_type, r.wait_time AS wait_ms,
       r.wait_resource
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.database_id = DB_ID() AND s.is_user_process = 1 AND r.session_id <> @@SPID;
-- The head of the chain, by going up blocking_session_id with a recursive CTE, among the
-- user sessions of the database: the engine's own tasks also wait, now and then.
WITH blocked AS (
    SELECT r.session_id, r.blocking_session_id
    FROM sys.dm_exec_requests AS r
    JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
    WHERE r.blocking_session_id <> 0
      AND r.database_id = DB_ID() AND s.is_user_process = 1
),
chain AS (
    SELECT b.session_id, b.blocking_session_id AS head, 1 AS depth
    FROM blocked AS b
    UNION ALL
    SELECT c.session_id, b.blocking_session_id, c.depth + 1
    FROM chain AS c
    JOIN blocked AS b ON b.session_id = c.head
)
SELECT head AS head_of_chain, COUNT(*) AS blocked_behind
FROM chain AS c
WHERE NOT EXISTS (SELECT * FROM blocked AS b WHERE b.session_id = c.head)
GROUP BY head;
-- The same with sp_WhoIsActive.
EXEC DBA.dbo.sp_WhoIsActive
     @find_block_leaders = 1,
     @sort_order = '[blocked_session_count] DESC',
     @filter_type = 'database', @filter = 'PachadataTraining_Ex14',
     @output_column_list = '[session_id][blocking_session_id][blocked_session_count][status][wait_info][open_tran_count][sql_text]';
-- Measured: window A first, sleeping, blocked_session_count 2, open_tran_count 1; window B
-- LCK_M_S, 1; window C LCK_M_X, 0, open_tran_count 2 (the UPDATE opens its own).
GO

-- ===== B. A history of the activity ====================================================
USE DBA;
GO
-- The procedure writes the CREATE TABLE of its own output, for exactly the parameters it
-- receives: the collection must use the same ones.
DECLARE @schema varchar(max);
EXEC dbo.sp_WhoIsActive @get_plans = 1, @find_block_leaders = 1,
     @return_schema = 1, @schema = @schema OUTPUT;
SET @schema = REPLACE(@schema, '<table_name>', 'DBA.dbo.ActivityHistory');
IF OBJECT_ID(N'dbo.ActivityHistory') IS NULL EXEC (@schema);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = N'CIX_ActivityHistory_collection_time')
    CREATE CLUSTERED INDEX CIX_ActivityHistory_collection_time
        ON dbo.ActivityHistory (collection_time);
GO
-- The job: a collection step, a purge step, every minute.
USE msdb;
GO
IF EXISTS (SELECT * FROM dbo.sysjobs WHERE name = N'Exercise 14 - Activity history')
    EXEC dbo.sp_delete_job @job_name = N'Exercise 14 - Activity history';
EXEC dbo.sp_add_job @job_name = N'Exercise 14 - Activity history';
EXEC dbo.sp_add_jobstep @job_name = N'Exercise 14 - Activity history',
     @step_name = N'Collect', @subsystem = N'TSQL', @database_name = N'DBA',
     @command = N'EXEC dbo.sp_WhoIsActive @get_plans = 1, @find_block_leaders = 1,
     @destination_table = ''DBA.dbo.ActivityHistory'';',
     @on_success_action = 3;
EXEC dbo.sp_add_jobstep @job_name = N'Exercise 14 - Activity history',
     @step_name = N'Purge', @subsystem = N'TSQL', @database_name = N'DBA',
     @command = N'DELETE FROM dbo.ActivityHistory WHERE collection_time < DATEADD(DAY, -7, GETDATE());';
EXEC dbo.sp_add_jobschedule @job_name = N'Exercise 14 - Activity history',
     @name = N'Every minute', @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 4, @freq_subday_interval = 1;
EXEC dbo.sp_add_jobserver @job_name = N'Exercise 14 - Activity history';
EXEC dbo.sp_start_job @job_name = N'Exercise 14 - Activity history';
GO
-- A few seconds later, then two minutes later: one collection per run.
SELECT collection_time, COUNT(*) AS sessions, MAX(blocked_session_count) AS max_blocked
FROM DBA.dbo.ActivityHistory
GROUP BY collection_time
ORDER BY collection_time;
EXEC DBA.dbo.sp_spaceused N'dbo.ActivityHistory';
GO

-- ===== C. Kill a large transaction =====================================================
-- First ROLLBACK in window A. Then run 4-big-transaction.sql, and this block when it waits.
USE PachadataTraining_Ex14;
GO
-- Look before KILL: who, since when, how much log, which locks.
SELECT st.session_id, s.login_name, s.program_name,
       dt.database_transaction_begin_time AS transaction_begin,
       dt.database_transaction_log_record_count AS log_records,
       dt.database_transaction_log_bytes_used / 1048576 AS log_mb
FROM sys.dm_tran_session_transactions AS st
JOIN sys.dm_tran_database_transactions AS dt ON dt.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
WHERE dt.database_id = DB_ID()
ORDER BY dt.database_transaction_log_bytes_used DESC;
SELECT request_session_id AS session_id, resource_type, request_mode, COUNT(*) AS locks
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID() AND resource_type NOT IN (N'DATABASE', N'METADATA')
  AND request_session_id IN (SELECT session_id FROM sys.dm_exec_sessions
                             WHERE is_user_process = 1)
GROUP BY request_session_id, resource_type, request_mode;
-- Measured: 503,935 log records, 80 MB of log; one X lock on the table per lock
-- partition (22 OBJECT lines on a host whose engine sees 22 schedulers), after escalation.
GO
-- Kill, then follow the rollback every half second until 6106 (the session is gone).
DECLARE @spid int =
    (SELECT TOP (1) st.session_id
     FROM sys.dm_tran_session_transactions AS st
     JOIN sys.dm_tran_database_transactions AS dt ON dt.transaction_id = st.transaction_id
     WHERE dt.database_id = DB_ID()
     ORDER BY dt.database_transaction_log_bytes_used DESC);
DECLARE @kill nvarchar(50) = CONCAT(N'KILL ', @spid),
        @status nvarchar(50) = CONCAT(N'KILL ', @spid, N' WITH STATUSONLY'), @i int = 0;
SELECT @spid AS killed, SYSDATETIME() AS killed_at;
EXEC (@kill);
WHILE @i < 60
BEGIN
    BEGIN TRY
        EXEC (@status);
    END TRY
    BEGIN CATCH
        SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message,
               SYSDATETIME() AS at;
        BREAK;
    END CATCH;
    SELECT percent_complete, status FROM sys.dm_exec_requests WHERE session_id = @spid;
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
-- Measured: first estimate 0 %, 251 seconds remaining; 53 % half a second later; 6106 one
-- second after the KILL. The window of 4-big-transaction.sql receives error 596 ("Cannot
-- continue the execution because the session is in the kill state", severity 21).
GO
