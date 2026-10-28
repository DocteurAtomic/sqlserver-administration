-- Clip 14.2: see the chain of windows 1, 2 and 3, with the DMVs, then with sp_WhoIsActive.
-- Played for the video on sqladm-14, in a fourth window, while windows 1 to 3 wait:
-- ci: skip (it needs the three windows, and sp_WhoIsActive from 02a-install-whoisactive.sh)
-- 1. sys.dm_exec_requests: who waits, behind whom, on what. Window 1 is not there: it runs
--    nothing, it sleeps with its transaction open. The engine's own tasks, which also work
--    in the database (the Query Store writes its data there), are left out.
-- 2. sys.dm_exec_sessions: window 1, sleeping, with one open transaction.
-- 3. sys.dm_tran_locks: the X lock granted to window 1, the two X locks that wait.
-- 4. sp_WhoIsActive without parameters, then with the head of the chain first.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The requests of the database.
SELECT r.session_id, r.blocking_session_id, r.status, r.wait_type,
       r.wait_time AS wait_ms, r.wait_resource
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.database_id = DB_ID() AND s.is_user_process = 1 AND r.session_id <> @@SPID;
-- 2. The sessions of the database, idle ones included.
SELECT s.session_id, s.status, s.open_transaction_count, s.login_name, s.program_name,
       s.last_request_end_time
FROM sys.dm_exec_sessions AS s
WHERE s.database_id = DB_ID() AND s.is_user_process = 1 AND s.session_id <> @@SPID;
-- 3. The locks of the user sessions, without the shared locks on the database and on
--    its metadata.
SELECT request_session_id AS session_id, resource_type, request_mode, request_status
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID() AND resource_type NOT IN (N'DATABASE', N'METADATA')
  AND request_session_id IN (SELECT session_id FROM sys.dm_exec_sessions
                             WHERE is_user_process = 1)
ORDER BY session_id, resource_type;
GO
-- 4. sp_WhoIsActive. Without parameters: the running requests and the sleeping sessions
--    that hold a transaction.
EXEC DBA.dbo.sp_WhoIsActive;
-- The head of the chain first: @find_block_leaders counts, for each session, every
-- session blocked behind it, at any depth.
EXEC DBA.dbo.sp_WhoIsActive
     @find_block_leaders = 1,
     @sort_order = '[blocked_session_count] DESC',
     @output_column_list = '[session_id][blocking_session_id][blocked_session_count][status][wait_info][open_tran_count][login_name][program_name][sql_text]';
