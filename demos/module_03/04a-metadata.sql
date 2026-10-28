-- Clip 3.4: the metadata. Runs on the lab, in one session, after 00-setup.sql. Reads the
-- database and changes nothing.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The same question asked to INFORMATION_SCHEMA, the SQL standard, and to the catalog
--    views of SQL Server: the columns of Contact.Contact.
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = N'Contact' AND TABLE_NAME = N'Contact'
ORDER BY ORDINAL_POSITION;

SELECT c.name AS column_name, t.name AS type_name, c.max_length, c.is_nullable,
       c.is_identity, c.is_computed, c.collation_name
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'Contact.Contact')
ORDER BY c.column_id;
GO
-- 2. What the standard views do not know: the indexes and the compression of the table.
SELECT i.name AS index_name, i.type_desc, p.data_compression_desc, p.rows
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Contact.Contact')
ORDER BY i.index_id;
GO
-- 3. The objects of the database, those of the sys schema that come from Resource, and both.
SELECT (SELECT COUNT(*) FROM sys.objects)                           AS objects,
       (SELECT COUNT(*) FROM sys.objects WHERE is_ms_shipped = 1)    AS shipped_by_microsoft,
       (SELECT COUNT(*) FROM sys.system_objects)                     AS system_objects,
       (SELECT COUNT(*) FROM sys.all_objects)                        AS all_objects;
GO
-- 4. Functions and procedures: a property, and the code of a system procedure, kept in
--    Resource.
SELECT DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery')  AS recovery,
       DATABASEPROPERTYEX(N'PachadataTraining', 'Collation') AS collation,
       OBJECT_ID(N'Contact.Contact')                         AS contact_object_id;

SELECT LEFT(OBJECT_DEFINITION(OBJECT_ID(N'sys.sp_helpdb')), 60) AS start_of_the_code;
GO
