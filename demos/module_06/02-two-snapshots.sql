-- Clip 6.1: the revert refused while two snapshots exist. Runs on the lab, in one session,
-- after 01-create-snapshot.sql.
-- ci: skip (part 2 ends on an expected error, which stops sqlcmd -b)
-- Run it part by part (select a part, then F5): part 2 fails on purpose.
USE master;
SET NOCOUNT ON;
GO
-- 1. A second snapshot, taken by a colleague after the release.
CREATE DATABASE PachadataTraining_AfterRelease
    ON (NAME = PachadataTraining,
        FILENAME = N'/var/opt/mssql/data/PachadataTraining_AfterRelease.ss')
    AS SNAPSHOT OF PachadataTraining;
SELECT name, create_date
FROM sys.databases
WHERE source_database_id = DB_ID(N'PachadataTraining');
GO
-- 2. The revert refuses (errors 3137, then 3013).
RESTORE DATABASE PachadataTraining
    FROM DATABASE_SNAPSHOT = N'PachadataTraining_BeforeRelease';
GO
-- 3. The other snapshot goes first.
DROP DATABASE PachadataTraining_AfterRelease;
GO
