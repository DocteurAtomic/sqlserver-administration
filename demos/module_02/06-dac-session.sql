-- Clip 2.6: inside the dedicated administrator connection (DAC). Run by 06-dac.sh through
-- sqlcmd -S admin:localhost, while two other sessions block each other.
-- ci: skip (it needs the DAC and two blocked sessions, which 06-dac.sh opens)
USE master;
SET NOCOUNT ON;
GO
-- 1. This session goes through the dedicated endpoint.
SELECT s.session_id, e.name AS endpoint_name, s.login_name,
       c.net_transport, c.local_tcp_port
FROM sys.dm_exec_sessions AS s
JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id
JOIN sys.dm_exec_connections AS c ON c.session_id = s.session_id
WHERE s.session_id = @@SPID;
GO
-- 2. A light query on the user sessions: what they run, and who blocks whom.
SELECT s.session_id, s.program_name, r.command, r.wait_type,
       r.blocking_session_id, s.open_transaction_count
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND s.program_name NOT LIKE N'SQLAgent%'
ORDER BY s.session_id;
GO
-- 3. The session at the head of the chain is killed: its transaction is rolled back.
DECLARE @head int = (SELECT TOP (1) r.blocking_session_id
                     FROM sys.dm_exec_requests AS r
                     WHERE r.blocking_session_id > 0
                       AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS b
                                       WHERE b.session_id = r.blocking_session_id
                                         AND b.blocking_session_id > 0));
DECLARE @kill nvarchar(30) = N'KILL ' + CAST(@head AS nvarchar(10)) + N';';
PRINT @kill;
IF @head IS NOT NULL EXEC (@kill);
GO
-- 4. The DAC stays open ten seconds, long enough for 06-dac.sh to try a second one.
WAITFOR DELAY '00:00:10';
GO
