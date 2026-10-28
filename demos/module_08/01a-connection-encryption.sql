-- Clip 8.1: is the connection encrypted? Runs on the lab, in one session. Reads only.
-- The same script, run with three sqlcmd options, shows three connections:
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C        < this file
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -N o   < this file
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -N s   < this file
USE master;
SET NOCOUNT ON;
GO
-- 1. The current connection: encrypted or not, and the version of TDS it speaks.
--    0x74000004 is TDS 7.4; 0x08000000 is TDS 8.0.
SELECT c.session_id, c.net_transport, c.protocol_type,
       CONVERT(varbinary(4), c.protocol_version) AS tds_version,
       c.encrypt_option, c.auth_scheme, s.program_name
FROM sys.dm_exec_connections AS c
JOIN sys.dm_exec_sessions AS s ON s.session_id = c.session_id
WHERE c.session_id = @@SPID;
-- 2. Every connection of the instance: the Agent's own connections too.
SELECT c.session_id, s.program_name, c.encrypt_option,
       CONVERT(varbinary(4), c.protocol_version) AS tds_version
FROM sys.dm_exec_connections AS c
JOIN sys.dm_exec_sessions AS s ON s.session_id = c.session_id
ORDER BY c.session_id;
GO
