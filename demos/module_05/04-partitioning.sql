-- Clip 5.4: partitioning. Runs on the lab, in one session, after 03-compression.sql.
-- It takes a few seconds.
-- The reporting table Enrollment.PartitionedEnrollment keeps every enrollment since 2010.
-- Accounting asks for fifteen years: 2010 is purged, 2011 goes to an archive table, and
-- next year must be ready before its first enrollment. Each partition operation runs in a
-- transaction, to read how much log it wrote.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The partitioning as delivered: the function, its boundaries, the scheme.
SELECT pf.name AS function_name, TYPE_NAME(pp.user_type_id) AS parameter_type,
       pf.boundary_value_on_right, pf.fanout AS partitions
FROM sys.partition_functions AS pf
JOIN sys.partition_parameters AS pp ON pp.function_id = pf.function_id;
SELECT prv.boundary_id, prv.value AS boundary
FROM sys.partition_range_values AS prv
JOIN sys.partition_functions AS pf ON pf.function_id = prv.function_id
WHERE pf.name = N'pfDateCreation';
SELECT ps.name AS scheme_name, dds.destination_id, ds.name AS filegroup_name
FROM sys.partition_schemes AS ps
JOIN sys.destination_data_spaces AS dds ON dds.partition_scheme_id = ps.data_space_id
JOIN sys.data_spaces AS ds ON ds.data_space_id = dds.data_space_id
ORDER BY dds.destination_id;
GO
-- 2. The partitions of the table, their lower boundary and their rows.
SELECT p.partition_number, prv.value AS lower_boundary, p.rows, p.data_compression_desc
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = ps.function_id AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'Enrollment.PartitionedEnrollment') AND p.index_id = 0
ORDER BY p.partition_number;
-- $PARTITION gives the partition of any value, whether a row exists or not.
SELECT $PARTITION.pfDateCreation('2010-06-30') AS p_2010, $PARTITION.pfDateCreation('2016-01-01') AS p_2016,
       $PARTITION.pfDateCreation('2030-01-01') AS p_2030;
GO
-- 3. An index created for the reports, placed explicitly on PRIMARY: not aligned.
CREATE INDEX ix_PartitionedEnrollment_SessionId
    ON Enrollment.PartitionedEnrollment (SessionId) ON [PRIMARY];
BEGIN TRY
    TRUNCATE TABLE Enrollment.PartitionedEnrollment
        WITH (PARTITIONS ($PARTITION.pfDateCreation('2010-06-30')));
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
-- The same index, created without ON: it follows the partition scheme of the table.
CREATE INDEX ix_PartitionedEnrollment_SessionId
    ON Enrollment.PartitionedEnrollment (SessionId) WITH (DROP_EXISTING = ON);
SELECT i.name AS index_name, i.type_desc, ds.name AS data_space, ds.type_desc AS data_space_type
FROM sys.indexes AS i
JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.PartitionedEnrollment');
GO
-- 4. Isolate 2010 and 2011: two new boundaries, cut inside the first partition, which holds
--    2010 to 2015. The scheme already has a NEXT USED filegroup for the first SPLIT; the
--    second needs one.
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfDateCreation() SPLIT RANGE ('2011-01-01');
SELECT N'SPLIT 2011' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
ALTER PARTITION SCHEME psDateCreation NEXT USED [PRIMARY];
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfDateCreation() SPLIT RANGE ('2012-01-01');
SELECT N'SPLIT 2012' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
SELECT p.partition_number, prv.value AS lower_boundary, p.rows
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = ps.function_id AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'Enrollment.PartitionedEnrollment') AND p.index_id = 0
ORDER BY p.partition_number;
GO
-- 5. Archive 2011. The target: empty, same columns, same compression, same filegroup.
CREATE TABLE Enrollment.EnrollmentArchive (
    EnrollmentId   int           NOT NULL,
    SessionId      int           NOT NULL,
    ContactId      int           NULL,
    CreationDate   smalldatetime NOT NULL,
    OrderReference varchar(100)  NULL
) ON [PRIMARY] WITH (DATA_COMPRESSION = ROW);
BEGIN TRANSACTION;
ALTER TABLE Enrollment.PartitionedEnrollment
    SWITCH PARTITION $PARTITION.pfDateCreation('2011-01-01') TO Enrollment.EnrollmentArchive;
SELECT N'SWITCH 2011' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
SELECT COUNT(*) AS archived_rows, MIN(CreationDate) AS first_date, MAX(CreationDate) AS last_date
FROM Enrollment.EnrollmentArchive;
GO
-- 6. Purge 2010 without archiving it, then remove the boundary of 2011: both partitions on
--    each side of it are empty.
BEGIN TRANSACTION;
TRUNCATE TABLE Enrollment.PartitionedEnrollment
    WITH (PARTITIONS ($PARTITION.pfDateCreation('2010-06-30')));
SELECT N'TRUNCATE 2010' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfDateCreation() MERGE RANGE ('2011-01-01');
SELECT N'MERGE 2011' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
GO
-- 7. Open 2027: the last partition holds 2019 to 2026, and nothing from 2027 yet.
ALTER PARTITION SCHEME psDateCreation NEXT USED [PRIMARY];
BEGIN TRANSACTION;
ALTER PARTITION FUNCTION pfDateCreation() SPLIT RANGE ('2027-01-01');
SELECT N'SPLIT 2027' AS operation, SUM(database_transaction_log_record_count) AS log_records,
       SUM(database_transaction_log_bytes_used) / 1024 AS log_kb
FROM sys.dm_tran_database_transactions WHERE database_id = DB_ID();
COMMIT;
GO
-- 8. What accounting asked for, and what the operations team got back.
SELECT p.partition_number, prv.value AS lower_boundary, p.rows
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS prv
       ON prv.function_id = ps.function_id AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID(N'Enrollment.PartitionedEnrollment') AND p.index_id = 0
ORDER BY p.partition_number;
SELECT YEAR(MIN(CreationDate)) AS first_year, COUNT(*) AS enrollments
FROM Enrollment.PartitionedEnrollment;
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       SUM(ps.used_page_count) AS used_pages, SUM(ps.used_page_count) / 128 AS used_mb
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Elearning.Activity'),
                       OBJECT_ID(N'Enrollment.EnrollmentArchive'))
GROUP BY ps.object_id
ORDER BY table_name;
GO
