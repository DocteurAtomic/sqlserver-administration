-- Clip 2.4: the ports the instance listens on, and the port of your own connection.
-- Runs on the lab, in one session, from SSMS on your computer. Reads only.
USE master;
SET NOCOUNT ON;
GO
-- 1. The TCP listeners: the instance (TSQL), the dedicated administrator connection (TSQL
--    too, on 1434), Service Broker.
SELECT ip_address, port, type_desc, state_desc
FROM sys.dm_tcp_listener_states
ORDER BY port, ip_address;
GO
-- 2. Your connection: transport, port on the server side, encryption.
SELECT net_transport, local_tcp_port, encrypt_option, auth_scheme
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
GO
-- 3. What the error log said at startup.
EXEC sys.xp_readerrorlog 0, 1, N'Server is listening on';
GO
