-- Module 2 exercise, starting point. Runs on your lab, in one session, in a second or two.
-- Creates the database ConfigLab02 and its table dbo.Server: five servers of PachaData,
-- the one of your lab among them, for which you write the configuration script.
-- It never writes in PachadataTraining. 2-solution.sql drops ConfigLab02 at the end.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'ConfigLab02') IS NOT NULL
BEGIN
    ALTER DATABASE ConfigLab02 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ConfigLab02;
END;
GO
CREATE DATABASE ConfigLab02;
GO
USE ConfigLab02;
GO
-- memory_mb: the physical memory of a Windows server, or the memory limit of the SQL Server
-- process on Linux (memory.memorylimitmb, 80 % of the machine or of the container by default).
CREATE TABLE dbo.Server (
    server_name     sysname     NOT NULL PRIMARY KEY,
    platform        varchar(10) NOT NULL CHECK (platform IN ('Windows', 'Linux')),
    memory_mb       int         NOT NULL,
    numa_nodes      int         NOT NULL,
    logical_per_node int        NOT NULL,
    workload        varchar(10) NOT NULL CHECK (workload IN ('OLTP', 'reporting'))
);
INSERT INTO dbo.Server (server_name, platform, memory_mb, numa_nodes, logical_per_node, workload)
VALUES ('PACHA-SQLDEV', 'Windows', 8192, 1, 4, 'OLTP'),
       ('PACHA-SQL01', 'Windows', 16384, 1, 8, 'OLTP'),
       ('PACHA-SQL02', 'Windows', 65536, 2, 12, 'OLTP'),
       ('PACHA-BI01', 'Windows', 262144, 4, 20, 'reporting'),
       ('PACHA-LAB', 'Linux', 3277, 2, 11, 'OLTP');
SELECT server_name, platform, memory_mb, numa_nodes, logical_per_node, workload
FROM dbo.Server
ORDER BY memory_mb;
GO
