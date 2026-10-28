-- Module 2 exercise, solution. Runs on your lab, in one session, after 1-start.sql, in a few
-- seconds. Parts 4 and 5 open other sessions: their commands are in comments, and what can
-- run in this session runs here.
-- At the end it gives the options of the instance back their values as the lab was
-- installed, and drops ConfigLab02.
USE ConfigLab02;
SET NOCOUNT ON;
GO
-- Part 1. The calculation, on the five servers.
-- Memory, Windows: physical memory minus the reserve of the system, 2 GB up to 16 GB, 4 GB
-- up to 64 GB, 10 % beyond (rule of the course, from the in-person training).
-- Memory, Linux: memory_mb is already the limit of the process, the system has its 20 %
-- outside of it; the buffer pool gets 75 % of the process (choice of the course).
-- MAXDOP, rule of Microsoft: one node, the number of logical processors up to 8, then 8;
-- several nodes, the number per node up to 16, then half of it, 16 at most. Then 8 at most
-- for an OLTP workload.
WITH rules AS (
    SELECT server_name, platform, memory_mb, numa_nodes, logical_per_node, workload,
           CASE
               WHEN platform = 'Linux' THEN memory_mb * 3 / 4
               WHEN memory_mb <= 16384 THEN memory_mb - 2048
               WHEN memory_mb <= 65536 THEN memory_mb - 4096
               ELSE memory_mb - memory_mb / 10
           END AS max_server_memory_mb,
           CASE
               WHEN numa_nodes = 1 AND logical_per_node <= 8 THEN logical_per_node
               WHEN numa_nodes = 1 THEN 8
               WHEN logical_per_node <= 16 THEN logical_per_node
               WHEN logical_per_node / 2 > 16 THEN 16
               ELSE logical_per_node / 2
           END AS maxdop_microsoft
    FROM dbo.Server
)
SELECT server_name, platform, memory_mb, max_server_memory_mb, maxdop_microsoft,
       CASE WHEN workload = 'OLTP' AND maxdop_microsoft > 8 THEN 8 ELSE maxdop_microsoft END AS maxdop
FROM rules
ORDER BY memory_mb;
GO
-- Part 2. The same calculation on the instance itself, from what it sees.
USE master;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
GO
DECLARE @platform nvarchar(256) = (SELECT host_platform FROM sys.dm_os_host_info),
        @memory_mb int = (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info),
        @nodes int, @per_node int, @max_mb int, @maxdop int;
SELECT @nodes = COUNT(*), @per_node = MAX(online_scheduler_count)
FROM sys.dm_os_nodes
WHERE node_state_desc = N'ONLINE';           -- leaves out node 64, the one of the DAC
SET @max_mb = CASE
                  WHEN @platform = N'Linux' THEN @memory_mb * 3 / 4
                  WHEN @memory_mb <= 16384 THEN @memory_mb - 2048
                  WHEN @memory_mb <= 65536 THEN @memory_mb - 4096
                  ELSE @memory_mb - @memory_mb / 10
              END;
SET @maxdop = CASE
                  WHEN @nodes = 1 AND @per_node <= 8 THEN @per_node
                  WHEN @nodes = 1 THEN 8
                  WHEN @per_node <= 16 THEN @per_node
                  WHEN @per_node / 2 > 16 THEN 16
                  ELSE @per_node / 2
              END;
IF @maxdop > 8 SET @maxdop = 8;
SELECT @platform AS host_platform, @memory_mb AS memory_mb, @nodes AS numa_nodes,
       @per_node AS logical_per_node, @max_mb AS max_server_memory_mb, @maxdop AS maxdop;
EXEC sys.sp_configure N'max server memory (MB)', @max_mb;
EXEC sys.sp_configure N'max degree of parallelism', @maxdop;
EXEC sys.sp_configure N'cost threshold for parallelism', 50;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 1;
EXEC sys.sp_configure N'backup compression default', 1;
EXEC sys.sp_configure N'remote admin connections', 1;
GO
-- Before RECONFIGURE, nothing is applied: value has changed, value_in_use not yet.
SELECT name, value, value_in_use
FROM sys.configurations
WHERE value <> value_in_use
ORDER BY name;
GO
RECONFIGURE;
GO
SELECT name, value, value_in_use
FROM sys.configurations
WHERE value <> value_in_use
ORDER BY name;
GO
-- Part 3. The ports. From SSMS on your computer, connected to localhost,14433, the
-- connection arrives on 1433: Docker forwards the port 14433 of your computer to the port
-- 1433 of the container, and SQL Server only sees the latter.
SELECT ip_address, port, type_desc
FROM sys.dm_tcp_listener_states
ORDER BY port, ip_address;
SELECT net_transport, local_tcp_port, encrypt_option
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
GO
-- Part 4. The DAC, in a terminal:
--   docker exec -it sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S admin:localhost -U sa -C
-- (or -S 127.0.0.1,1434). Inside it, the endpoint of the session:
--   SELECT e.name FROM sys.dm_exec_sessions AS s
--   JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE s.session_id = @@SPID;
-- It returns Dedicated Admin Connection. A second one, from another terminal, fails before
-- the login; the error log says why. From an ordinary session:
EXEC sys.xp_readerrorlog 0, 1, N'Dedicated admin connection';
EXEC sys.xp_readerrorlog 0, 1, N'17810';
GO
-- Part 5. The DAC from the network. remote admin connections at 1 moved the listener of the
-- port 1434 from the loopback (127.0.0.1) to every address (0.0.0.0):
SELECT ip_address, port FROM sys.dm_tcp_listener_states WHERE port = 1434;
-- From the network, the client must give the port, there is no SQL Browser on Linux:
--   docker exec -it sqladmcourse sh -c '/opt/mssql-tools18/bin/sqlcmd -S "$(hostname),1434" -U sa -C'
-- From your computer, the port 1434 of the container is not published by compose.yaml:
-- a line "127.0.0.1:14434:1434" under ports, and a new container, would open it.
GO
-- Cleanup: the options as the lab was installed, and the database of the exercise.
EXEC sys.sp_configure N'max server memory (MB)', 2147483647;
EXEC sys.sp_configure N'max degree of parallelism', 0;
EXEC sys.sp_configure N'cost threshold for parallelism', 5;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 0;
EXEC sys.sp_configure N'backup compression default', 0;
EXEC sys.sp_configure N'remote admin connections', 0;
RECONFIGURE;
GO
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
GO
IF DB_ID(N'ConfigLab02') IS NOT NULL
BEGIN
    ALTER DATABASE ConfigLab02 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ConfigLab02;
END;
GO
