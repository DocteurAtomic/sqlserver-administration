-- Clip 5.2: tables, types and constraints. Runs on the lab, in one session, after
-- 01-pages-and-heaps.sql. It takes a few seconds.
-- What a DBA checks on the tables of a database taken over from another team: the
-- constraints the engine no longer trusts, the foreign keys without an index, the types
-- that waste space, the identity columns and their gaps.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The constraints the engine no longer trusts, foreign keys and check constraints.
SELECT N'FOREIGN KEY' AS constraint_type, OBJECT_SCHEMA_NAME(parent_object_id) + N'.'
       + OBJECT_NAME(parent_object_id) AS table_name, name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE is_not_trusted = 1
UNION ALL
SELECT N'CHECK', OBJECT_SCHEMA_NAME(parent_object_id) + N'.' + OBJECT_NAME(parent_object_id),
       name, is_disabled, is_not_trusted
FROM sys.check_constraints
WHERE is_not_trusted = 1;
GO
-- 2. What it costs: the number of enrollments that have a session. With a trusted foreign
--    key on a NOT NULL column, the optimizer knows every enrollment has its session and
--    removes the join.
SET STATISTICS IO ON;
SELECT COUNT(*) AS enrollments
FROM Enrollment.Enrollment AS e
JOIN Course.Session AS s ON s.SessionId = e.SessionId;
SET STATISTICS IO OFF;
GO
-- 3. The correction: WITH CHECK reads the whole table and checks every row.
ALTER TABLE Enrollment.Enrollment WITH CHECK CHECK CONSTRAINT fk_Enrollment_Session;
SELECT name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE name = N'fk_Enrollment_Session';
SET STATISTICS IO ON;
SELECT COUNT(*) AS enrollments
FROM Enrollment.Enrollment AS e
JOIN Course.Session AS s ON s.SessionId = e.SessionId;
SET STATISTICS IO OFF;
GO
-- 4. The single-column foreign keys whose column leads no index: deleting or changing a
--    parent row then scans the child table.
WITH fk AS (
    SELECT fk.name, fkc.parent_object_id, fkc.parent_column_id,
           CASE WHEN EXISTS (SELECT 1 FROM sys.index_columns AS ic
                             WHERE ic.object_id = fkc.parent_object_id
                               AND ic.column_id = fkc.parent_column_id
                               AND ic.key_ordinal = 1) THEN 1 ELSE 0 END AS has_index
    FROM sys.foreign_keys AS fk
    JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
    WHERE NOT EXISTS (SELECT 1 FROM sys.foreign_key_columns AS c
                      WHERE c.constraint_object_id = fk.object_id AND c.constraint_column_id > 1)
)
SELECT COUNT(*) AS foreign_keys, SUM(1 - has_index) AS without_index
FROM fk;
SELECT TOP (5) OBJECT_SCHEMA_NAME(fkc.parent_object_id) + N'.' + OBJECT_NAME(fkc.parent_object_id) AS table_name,
       fk.name AS foreign_key, COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS column_name,
       p.rows AS table_rows
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.partitions AS p ON p.object_id = fkc.parent_object_id AND p.index_id IN (0, 1)
WHERE NOT EXISTS (SELECT 1 FROM sys.index_columns AS ic
                  WHERE ic.object_id = fkc.parent_object_id
                    AND ic.column_id = fkc.parent_column_id
                    AND ic.key_ordinal = 1)
  AND NOT EXISTS (SELECT 1 FROM sys.foreign_key_columns AS c
                  WHERE c.constraint_object_id = fk.object_id AND c.constraint_column_id > 1)
ORDER BY p.rows DESC;
GO
-- 5. The types. The same million prospects stored three ways: varchar, nvarchar, and every
--    column declared varchar(max).
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       SUM(ps.row_count) AS row_count, SUM(ps.in_row_used_page_count) AS in_row_pages,
       SUM(ps.lob_used_page_count) AS lob_pages, SUM(ps.used_page_count) / 128 AS used_mb
FROM sys.dm_db_partition_stats AS ps
WHERE ps.object_id IN (OBJECT_ID(N'Contact.ProspectUS_SQL_Latin1'), OBJECT_ID(N'Contact.ProspectUS_N'),
                       OBJECT_ID(N'Contact.ProspectUS_MAX'))
  AND ps.index_id = 0
GROUP BY ps.object_id
ORDER BY in_row_pages;
-- The types to replace, deprecated since SQL Server 2005, and the columns declared (max).
SELECT TYPE_NAME(c.user_type_id) AS type_name, COUNT(*) AS columns
FROM sys.columns AS c
JOIN sys.tables AS t ON t.object_id = c.object_id
WHERE TYPE_NAME(c.user_type_id) IN (N'text', N'ntext', N'image')
   OR (c.max_length = -1 AND TYPE_NAME(c.user_type_id) IN (N'varchar', N'nvarchar', N'varbinary'))
GROUP BY TYPE_NAME(c.user_type_id);
GO
-- 6. The identity columns: last value given, and how far it is from the maximum of its type.
SELECT TOP (5) OBJECT_SCHEMA_NAME(ic.object_id) + N'.' + OBJECT_NAME(ic.object_id) AS table_name,
       ic.name AS column_name, TYPE_NAME(ic.user_type_id) AS type_name,
       CAST(ic.last_value AS bigint) AS last_value,
       (SELECT SUM(p.rows) FROM sys.partitions AS p
        WHERE p.object_id = ic.object_id AND p.index_id IN (0, 1)) AS row_count,
       CAST(100.0 * CAST(ic.last_value AS bigint)
            / CASE TYPE_NAME(ic.user_type_id) WHEN N'tinyint' THEN 255 WHEN N'smallint' THEN 32767
                   WHEN N'int' THEN 2147483647 ELSE 9223372036854775807 END AS decimal(9, 4)) AS pct_of_max
FROM sys.identity_columns AS ic
WHERE ic.last_value IS NOT NULL
  AND OBJECTPROPERTY(ic.object_id, 'IsMSShipped') = 0
ORDER BY pct_of_max DESC;
GO
-- 7. A rolled-back insert still consumes its identity value. The same goes for a sequence.
SELECT IDENT_CURRENT(N'Trainer.TrainerRate') AS identity_before;
BEGIN TRANSACTION;
INSERT INTO Trainer.TrainerRate (TrainerId, StartDate, DailyRate) VALUES (1, '2027-01-01', 900.00);
ROLLBACK;
SELECT IDENT_CURRENT(N'Trainer.TrainerRate') AS identity_after_rollback;
GO
CREATE SEQUENCE dbo.DemoInvoiceNumber AS int START WITH 500000 INCREMENT BY 1;
BEGIN TRANSACTION;
SELECT NEXT VALUE FOR dbo.DemoInvoiceNumber AS number_taken;
ROLLBACK;
SELECT NEXT VALUE FOR dbo.DemoInvoiceNumber AS next_number;
DROP SEQUENCE dbo.DemoInvoiceNumber;
GO
