-- Clip 9.3: ledger tables for the consents of the contacts. Runs on the lab, in one
-- session, after 00-setup.sql. It takes a second, and only changes PachadataTraining.
-- 1. An updatable ledger table, Contact.Consent, and the history table and ledger view
--    that the engine creates with it.
-- 2. Three consents, an update, a delete; the history read through the ledger view.
-- 3. An append-only ledger table, Contact.ConsentExport, and what both forms refuse.
-- 4. A digest, and the verification of the ledger against it (snapshot isolation needed).
-- 5. A dropped ledger table stays in the ledger, renamed.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The updatable ledger table: system versioning and the ledger, together.
CREATE TABLE Contact.Consent (
    ContactId int NOT NULL CONSTRAINT PK_Consent PRIMARY KEY,
    Newsletter bit NOT NULL,
    Partners bit NOT NULL
)
WITH (SYSTEM_VERSIONING = ON, LEDGER = ON);
GO
SELECT t.name AS ledger_table, t.ledger_type_desc,
       h.name AS history_table, v.name AS ledger_view
FROM sys.tables AS t
LEFT JOIN sys.tables AS h ON h.object_id = t.history_table_id
LEFT JOIN sys.views AS v ON v.object_id = t.ledger_view_id
WHERE t.name = N'Consent';
GO
-- 2. Three consents in one transaction; contact 8 then accepts the partners' offers, and
--    contact 9 asks to be forgotten.
INSERT INTO Contact.Consent (ContactId, Newsletter, Partners)
VALUES (6, 1, 0), (8, 1, 0), (9, 0, 0);
UPDATE Contact.Consent SET Partners = 1 WHERE ContactId = 8;
DELETE FROM Contact.Consent WHERE ContactId = 9;
GO
SELECT v.ContactId, v.Newsletter, v.Partners, v.ledger_operation_type_desc,
       t.transaction_id, t.principal_name
FROM Contact.Consent_Ledger AS v
JOIN sys.database_ledger_transactions AS t ON t.transaction_id = v.ledger_transaction_id
ORDER BY v.ledger_transaction_id, v.ledger_sequence_number;
GO
-- 3. The append-only form, for a log: every export of the consents to the mailing tool.
CREATE TABLE Contact.ConsentExport (
    ExportId int IDENTITY NOT NULL,
    Recipient nvarchar(100) NOT NULL,
    ContactCount int NOT NULL,
    ExportedAt datetime2(0) NOT NULL CONSTRAINT DF_ConsentExport_ExportedAt DEFAULT (SYSDATETIME())
)
WITH (LEDGER = ON (APPEND_ONLY = ON));
GO
INSERT INTO Contact.ConsentExport (Recipient, ContactCount) VALUES (N'Mailing tool', 1);
-- The refusal is raised when the statement compiles: EXECUTE lets TRY ... CATCH catch it.
BEGIN TRY
    EXECUTE (N'UPDATE Contact.ConsentExport SET ContactCount = 0;');
END TRY
BEGIN CATCH
    SELECT N'UPDATE append-only' AS attempt, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
BEGIN TRY
    EXECUTE (N'TRUNCATE TABLE Contact.Consent;');
END TRY
BEGIN CATCH
    SELECT N'TRUNCATE updatable' AS attempt, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 4. The digest: the hash of the last block, as a JSON document. The verification reads it
--    back, and needs snapshot isolation, off in the delivered database.
CREATE TABLE #digest (latest_digest nvarchar(max));
INSERT INTO #digest EXECUTE sys.sp_generate_database_ledger_digest;
SELECT latest_digest FROM #digest;
GO
SELECT snapshot_isolation_state_desc FROM sys.databases WHERE name = DB_NAME();
DECLARE @digest nvarchar(max) = (SELECT latest_digest FROM #digest);
BEGIN TRY
    EXECUTE sys.sp_verify_database_ledger @digests = @digest;
END TRY
BEGIN CATCH
    SELECT N'without snapshot isolation' AS attempt, ERROR_NUMBER() AS error,
           ERROR_MESSAGE() AS message;
END CATCH;
GO
ALTER DATABASE CURRENT SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
DECLARE @digest nvarchar(max) = (SELECT latest_digest FROM #digest);
EXECUTE sys.sp_verify_database_ledger @digests = @digest;
DROP TABLE #digest;
GO
-- 5. A ledger table is never really dropped: it is renamed, and stays in the ledger.
DROP TABLE Contact.ConsentExport;
GO
SELECT name, ledger_type_desc, is_dropped_ledger_table
FROM sys.tables
WHERE is_dropped_ledger_table = 1;
GO
