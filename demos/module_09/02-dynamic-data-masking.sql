-- Clip 9.2: dynamic data masking on the contacts. Runs on the lab, in one session, after
-- 01-row-level-security.sql: the representatives see their own contacts only, and now
-- masked. It takes a second, and only changes PachadataTraining.
-- 1. Before: Margaux reads the e-mail, phones and birth date of her contacts in clear.
-- 2. Four masks, and their list in sys.masked_columns.
-- 3. What Margaux and dbo see.
-- 4. UNMASK at three levels (granular since SQL Server 2022): a column, a table, a schema.
-- 5. What masking does not stop: the WHERE clause works on the real values, so a loop of
--    LIKE rebuilds a masked mobile number.
-- 6. An expression on a masked column comes out masked by default().
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Before any mask.
EXECUTE AS USER = N'Margaux';
SELECT TOP (3) ContactId, LastName, Email, Phone, Mobile, BirthDate
FROM Contact.Contact
WHERE Mobile IS NOT NULL
ORDER BY ContactId;
REVERT;
GO
-- 2. The masks. ALTER ANY MASK and ALTER on the table are needed; the stored values do not
--    change.
ALTER TABLE Contact.Contact ALTER COLUMN Email
    ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE Contact.Contact ALTER COLUMN Phone
    ADD MASKED WITH (FUNCTION = 'partial(2, "XXXXXX", 2)');
ALTER TABLE Contact.Contact ALTER COLUMN Mobile
    ADD MASKED WITH (FUNCTION = 'default()');
ALTER TABLE Contact.Contact ALTER COLUMN BirthDate
    ADD MASKED WITH (FUNCTION = 'datetime("D")');
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS masked_table,
       name AS column_name, masking_function
FROM sys.masked_columns
ORDER BY column_id;
GO
-- 3. Margaux, without UNMASK; dbo sees in clear, as sysadmin and db_owner always do.
EXECUTE AS USER = N'Margaux';
SELECT TOP (3) ContactId, LastName, Email, Phone, Mobile, BirthDate
FROM Contact.Contact
WHERE Mobile IS NOT NULL
ORDER BY ContactId;
REVERT;
SELECT TOP (3) ContactId, LastName, Email, Phone, Mobile, BirthDate
FROM Contact.Contact
WHERE ContactId IN (6, 8, 9)
ORDER BY ContactId;
GO
-- 4. UNMASK, from the narrowest to the widest. The representatives need the e-mail
--    address to write to their clients; Helene, their manager, reads the whole table.
GRANT UNMASK ON Contact.Contact (Email) TO SalesReps;   -- one column
GRANT UNMASK ON Contact.Contact TO Helene;              -- one table
-- GRANT UNMASK ON SCHEMA::Contact TO ...;              -- a schema
-- GRANT UNMASK TO ...;                                 -- the whole database
GO
SELECT USER_NAME(grantee_principal_id) AS grantee, class_desc,
       OBJECT_SCHEMA_NAME(major_id) + N'.' + OBJECT_NAME(major_id) AS object_name,
       COL_NAME(major_id, minor_id) AS column_name
FROM sys.database_permissions
WHERE permission_name = N'UNMASK';
GO
EXECUTE AS USER = N'Margaux';
SELECT N'Margaux' AS reader, ContactId, Email, Phone, Mobile, BirthDate
FROM Contact.Contact WHERE ContactId = 8;
REVERT;
EXECUTE AS USER = N'Helene';
SELECT N'Helene' AS reader, ContactId, Email, Phone, Mobile, BirthDate
FROM Contact.Contact WHERE ContactId = 8;
REVERT;
GO
-- 5. The mask applies to the result, not to the WHERE clause. Margaux sees xxxx for the
--    mobile of contact 8; she tries every digit at every position, and counts her queries.
EXECUTE AS USER = N'Margaux';
DECLARE @found varchar(15) = '', @digit int, @tries int = 0, @hit bit = 1;
WHILE @hit = 1
BEGIN
    SET @hit = 0;
    SET @digit = 0;
    WHILE @digit <= 9 AND @hit = 0
    BEGIN
        SET @tries += 1;
        IF EXISTS (SELECT 1 FROM Contact.Contact
                   WHERE ContactId = 8 AND Mobile LIKE @found + CHAR(48 + @digit) + '%')
        BEGIN
            SET @found += CHAR(48 + @digit);
            SET @hit = 1;
        END;
        SET @digit += 1;
    END;
END;
SELECT (SELECT Mobile FROM Contact.Contact WHERE ContactId = 8) AS mobile_shown,
       @found AS mobile_found, @tries AS queries;
-- The exact birth date, the same way: the row comes back when the guess is right.
SELECT ContactId, BirthDate AS birth_date_shown
FROM Contact.Contact
WHERE ContactId = 8 AND BirthDate = '1985-10-20';
REVERT;
GO
-- 6. An expression on a masked column is masked by default(), whatever the column's function.
EXECUTE AS USER = N'Margaux';
SELECT TOP (2) ContactId, UPPER(Email) AS email_upper, LEFT(Phone, 4) AS phone_start,
       YEAR(BirthDate) AS birth_year
FROM Contact.Contact
WHERE Mobile IS NOT NULL
ORDER BY ContactId;
REVERT;
GO
