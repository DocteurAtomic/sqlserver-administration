-- Clip 9.1: row-level security on the sales territories. Runs on the lab, in one session,
-- after 00-setup.sql. It takes a second, and only changes PachadataTraining.
-- 1. Before: every representative reads all the companies.
-- 2. The predicate function and the security policy: a filter on Contact.Company and
--    Contact.Contact, through the table of assignments.
-- 3. The same reads, filtered; an update outside the territory finds no row.
-- 4. The assignments themselves: a filter and two block predicates, so that nobody hands a
--    company over to a colleague or claims one in a colleague's name (error 33504).
-- 5. What the policy does not stop: an error that reveals a row the user cannot see.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Before any policy: Margaux reads the 2,000 companies of PachaData.
EXECUTE AS USER = N'Margaux';
SELECT USER_NAME() AS reader, COUNT(*) AS companies FROM Contact.Company;
REVERT;
GO
-- 2. The RLS objects live in their own schema. The function returns a row when the company
--    belongs to the current user, or when the user is a manager or db_owner.
CREATE SCHEMA Security AUTHORIZATION dbo;
GO
CREATE FUNCTION Security.fn_CompanyAccess (@CompanyId AS int)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS access
    WHERE EXISTS (SELECT 1 FROM Sales.CompanyAssignment AS a
                  WHERE a.CompanyId = @CompanyId AND a.SalesRep = USER_NAME())
       OR IS_MEMBER(N'SalesManagers') = 1
       OR IS_MEMBER(N'db_owner') = 1;
GO
CREATE FUNCTION Security.fn_SalesRepAccess (@SalesRep AS sysname)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS access
    WHERE @SalesRep = USER_NAME()
       OR IS_MEMBER(N'SalesManagers') = 1
       OR IS_MEMBER(N'db_owner') = 1;
GO
CREATE SECURITY POLICY Security.SalesTerritory
    ADD FILTER PREDICATE Security.fn_CompanyAccess(CompanyId) ON Contact.Company,
    ADD FILTER PREDICATE Security.fn_CompanyAccess(CompanyId) ON Contact.Contact,
    ADD FILTER PREDICATE Security.fn_SalesRepAccess(SalesRep) ON Sales.CompanyAssignment,
    ADD BLOCK PREDICATE Security.fn_SalesRepAccess(SalesRep) ON Sales.CompanyAssignment AFTER INSERT,
    ADD BLOCK PREDICATE Security.fn_SalesRepAccess(SalesRep) ON Sales.CompanyAssignment AFTER UPDATE
    WITH (STATE = ON);
GO
SELECT p.name AS policy, OBJECT_SCHEMA_NAME(pr.target_object_id) + N'.'
       + OBJECT_NAME(pr.target_object_id) AS target_table,
       pr.predicate_type_desc, pr.operation_desc, pr.predicate_definition
FROM sys.security_policies AS p
JOIN sys.security_predicates AS pr ON pr.object_id = p.object_id
ORDER BY target_table, pr.predicate_type_desc DESC, pr.operation_desc;
GO
-- 3. The same reads, filtered without a WHERE in the query.
EXECUTE AS USER = N'Margaux';
SELECT USER_NAME() AS reader,
       (SELECT COUNT(*) FROM Contact.Company) AS companies,
       (SELECT COUNT(*) FROM Contact.Contact) AS contacts;
REVERT;
EXECUTE AS USER = N'Lukas';
SELECT USER_NAME() AS reader,
       (SELECT COUNT(*) FROM Contact.Company) AS companies,
       (SELECT COUNT(*) FROM Contact.Contact) AS contacts;
REVERT;
EXECUTE AS USER = N'Helene';
SELECT USER_NAME() AS reader,
       (SELECT COUNT(*) FROM Contact.Company) AS companies,
       (SELECT COUNT(*) FROM Contact.Contact) AS contacts;
REVERT;
SELECT USER_NAME() AS reader,
       (SELECT COUNT(*) FROM Contact.Company) AS companies,
       (SELECT COUNT(*) FROM Contact.Contact) AS contacts;
GO
-- Company 5 is French, company 10 German. Margaux updates the phone number of both: the
-- filter hides company 10 from the UPDATE, which finds no row and raises no error.
SELECT c.CompanyId, c.Name, c.CountryCode, a.SalesRep
FROM Contact.Company AS c JOIN Sales.CompanyAssignment AS a ON a.CompanyId = c.CompanyId
WHERE c.CompanyId IN (5, 10);
EXECUTE AS USER = N'Margaux';
UPDATE Contact.Company SET Phone1 = Phone1 WHERE CompanyId = 5;
SELECT 5 AS company, @@ROWCOUNT AS rows_updated;
UPDATE Contact.Company SET Phone1 = Phone1 WHERE CompanyId = 10;
SELECT 10 AS company, @@ROWCOUNT AS rows_updated;
REVERT;
GO
-- 4. The assignments. Margaux sees her rows only. She claims the new company 1991 for
--    herself, which is allowed. She claims company 1992 in Sofia's name, then hands her
--    company 5 over to Lukas: both are refused by the block predicates. Without them, both
--    writes would succeed, and the rows would leave her view.
EXECUTE AS USER = N'Margaux';
SELECT COUNT(*) AS assignments_seen FROM Sales.CompanyAssignment;
INSERT INTO Sales.CompanyAssignment (CompanyId, SalesRep) VALUES (1991, N'Margaux');
SELECT COUNT(*) AS assignments_seen FROM Sales.CompanyAssignment;
BEGIN TRY
    INSERT INTO Sales.CompanyAssignment (CompanyId, SalesRep) VALUES (1992, N'Sofia');
END TRY
BEGIN CATCH
    SELECT N'insert for Sofia' AS attempt, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
BEGIN TRY
    UPDATE Sales.CompanyAssignment SET SalesRep = N'Lukas' WHERE CompanyId = 5;
END TRY
BEGIN CATCH
    SELECT N'hand over' AS attempt, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
-- 5. A side channel. Company 10 is hidden from Margaux, yet a conversion that fails on its
--    name tells her that the row exists: the error comes before the security predicate.
EXECUTE AS USER = N'Margaux';
BEGIN TRY
    SELECT CompanyId FROM Contact.Company
    WHERE CompanyId = 10 AND CONVERT(int, Name) = 1;
    SELECT N'no error' AS outcome;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
-- The same query on a company id that does not exist returns nothing, without error.
BEGIN TRY
    SELECT CompanyId FROM Contact.Company
    WHERE CompanyId = 9999 AND CONVERT(int, Name) = 1;
    SELECT N'no error' AS outcome;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
