-- Clip 14.2: end the head of the chain. Played for the video on sqladm-14, in the fourth
-- window, while windows 1 to 3 wait:
-- ci: skip (it kills window 1)
-- 1. Before KILL, what the head is: its login, its program, since when its transaction is
--    open, how much log it wrote. A night batch that has been running for three hours
--    costs three hours of rollback.
-- 2. KILL, built from the session number found: in SSMS, KILL followed by the number typed
--    by hand does the same. The rollback of one row is immediate; KILL ... WITH STATUSONLY
--    follows a long one.
-- 3. After: no request waits any more in the database.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The head: a session that blocks others and waits for nobody.
DECLARE @head int =
    (SELECT TOP (1) r.blocking_session_id
     FROM sys.dm_exec_requests AS r
     WHERE r.blocking_session_id <> 0
       AND r.database_id = DB_ID()
       AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS b
                       WHERE b.session_id = r.blocking_session_id
                         AND b.blocking_session_id <> 0));
SELECT s.session_id, s.login_name, s.host_name, s.program_name, s.status,
       dt.database_transaction_begin_time AS transaction_begin,
       dt.database_transaction_log_record_count AS log_records,
       dt.database_transaction_log_bytes_used AS log_bytes
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_tran_session_transactions AS st ON st.session_id = s.session_id
JOIN sys.dm_tran_database_transactions AS dt
  ON dt.transaction_id = st.transaction_id AND dt.database_id = DB_ID()
WHERE s.session_id = @head;
-- 2. KILL does not take a variable: the statement is built.
DECLARE @kill nvarchar(30) = CONCAT(N'KILL ', @head, N';');
PRINT @kill;
EXEC (@kill);
WAITFOR DELAY '00:00:01';
GO
-- 3. Nobody waits any more.
SELECT COUNT(*) AS blocked_requests
FROM sys.dm_exec_requests
WHERE database_id = DB_ID() AND blocking_session_id <> 0;
