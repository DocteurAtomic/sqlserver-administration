-- Clip 2.6: the proof that the request is met. Runs on the lab, in one session. Reads only.
-- On the lab of the video, after 05-configure-instance.sql; on a lab at its defaults, every
-- line but the first says what is missing.
USE master;
SET NOCOUNT ON;
GO
SELECT N'Instant File Initialization' AS item,
       instant_file_initialization_enabled AS value,
       CASE instant_file_initialization_enabled WHEN N'Y' THEN N'ok' ELSE N'grant the privilege' END AS verdict
FROM sys.dm_server_services
WHERE servicename LIKE N'MSSQLSERVER%' OR servicename LIKE N'SQL Server (%'
UNION ALL
SELECT name, CAST(value_in_use AS nvarchar(20)),
       CASE
           WHEN name = N'max server memory (MB)' AND CAST(value_in_use AS int) = 2147483647 THEN N'set a limit'
           WHEN name = N'max degree of parallelism' AND CAST(value_in_use AS int) = 0 THEN N'set a value'
           WHEN name = N'cost threshold for parallelism' AND CAST(value_in_use AS int) < 25 THEN N'raise it'
           WHEN name IN (N'optimize for ad hoc workloads', N'backup compression default',
                         N'remote admin connections') AND CAST(value_in_use AS int) = 0 THEN N'set to 1'
           ELSE N'ok'
       END
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism', N'optimize for ad hoc workloads',
               N'backup compression default', N'remote admin connections')
UNION ALL
SELECT N'DAC listener', ip_address + N' ' + CAST(port AS nvarchar(10)),
       CASE WHEN ip_address IN (N'0.0.0.0', N'::') THEN N'ok' ELSE N'local only' END
FROM sys.dm_tcp_listener_states
WHERE port = 1434 AND is_ipv4 = 1;
GO
