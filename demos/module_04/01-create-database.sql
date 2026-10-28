-- Clip 4.1: create a database. Runs on the lab, in one session, after 00-setup.sql.
-- It takes about a minute: part 4 copies 3.9 million rows.
-- The archive database of the e-learning activity: a small PRIMARY filegroup for the
-- catalog, a default filegroup ARCHIVE of two files of the same size, and a log left at
-- the sizes of model (8 MB, growing by 64 MB). The next clip looks at that log.
USE master;
SET NOCOUNT ON;
GO
-- 1. What a database created without any file clause would get: the files of model.
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb, is_percent_growth
FROM model.sys.database_files;
GO
-- 2. The database, its files and its filegroups.
CREATE DATABASE PachadataArchive
ON PRIMARY
    (NAME = PachadataArchive_sys, FILENAME = N'/var/opt/mssql/data/PachadataArchive_sys.mdf',
     SIZE = 64MB, FILEGROWTH = 64MB),
FILEGROUP ARCHIVE DEFAULT
    (NAME = PachadataArchive_a1, FILENAME = N'/var/opt/mssql/data/PachadataArchive_a1.ndf',
     SIZE = 256MB, FILEGROWTH = 256MB),
    (NAME = PachadataArchive_a2, FILENAME = N'/var/opt/mssql/data/PachadataArchive_a2.ndf',
     SIZE = 256MB, FILEGROWTH = 256MB)
LOG ON
    (NAME = PachadataArchive_log, FILENAME = N'/var/opt/mssql/data/PachadataArchive_log.ldf',
     SIZE = 8MB, FILEGROWTH = 64MB);
GO
ALTER DATABASE PachadataArchive MODIFY FILEGROUP ARCHIVE AUTOGROW_ALL_FILES;
-- An archive needs no point-in-time restore: SIMPLE (module 12 details the recovery models).
ALTER DATABASE PachadataArchive SET RECOVERY SIMPLE;
GO
USE PachadataArchive;
SELECT fg.name AS filegroup_name, fg.is_default, fg.is_autogrow_all_files, f.name AS file_name,
       f.type_desc, f.size / 128 AS size_mb, f.growth / 128 AS growth_mb, f.physical_name
FROM sys.database_files AS f
LEFT JOIN sys.filegroups AS fg ON fg.data_space_id = f.data_space_id
ORDER BY f.file_id;
GO
-- 3. The table, without an ON clause: it goes to the default filegroup.
CREATE TABLE dbo.Activity (
    ActivityId      bigint       NOT NULL CONSTRAINT PK_Activity PRIMARY KEY CLUSTERED,
    EventTime       datetime2(0) NOT NULL,
    ContactId       int          NOT NULL,
    EnrollmentId    int          NOT NULL,
    ModuleId        int          NULL,
    EventTypeCode   char(4)      NOT NULL,
    Step            smallint     NULL,
    DurationSeconds int          NULL,
    Score           tinyint      NULL,
    Device          char(1)      NULL
);
SELECT OBJECT_NAME(i.object_id) AS table_name, i.name AS index_name, ds.name AS data_space
FROM sys.indexes AS i
JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'dbo.Activity');
GO
-- 4. The archive: the activity before 2023, read from PachadataTraining.
INSERT INTO dbo.Activity
SELECT ActivityId, EventTime, ContactId, EnrollmentId, ModuleId, EventTypeCode, Step,
       DurationSeconds, Score, Device
FROM PachadataTraining.Elearning.Activity
WHERE EventTime < '2023-01-01';
SELECT @@ROWCOUNT AS rows_copied;
GO
-- 5. Where the pages went: proportional fill shares them between the two files.
SELECT name AS file_name, size / 128 AS size_mb,
       FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb,
       (size - FILEPROPERTY(name, 'SpaceUsed')) / 128 AS free_mb
FROM sys.database_files
WHERE type_desc = N'ROWS'
ORDER BY file_id;
GO
