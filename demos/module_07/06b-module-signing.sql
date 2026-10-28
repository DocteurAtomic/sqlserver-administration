-- Clip 7.6: dynamic SQL breaks the ownership chain, and the signature of the procedure by a
-- certificate repairs it. Played for the video on the throwaway container sqladm-07, after
-- 06a-ownership-chain.sql:
-- ci: skip (it needs the login of 02a-logins-users.sql)
-- On your lab, run it part by part: parts 2 and 5 end on the expected error 229. The
-- certificate lives in PachadataTraining, protected by its own password: no master key needed.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The search page of the website: sessions of a course, with the seats taken, by dynamic
--    SQL that adds only the filters given. Schema Web, owned by dbo.
CREATE SCHEMA Web AUTHORIZATION dbo;
GO
CREATE PROCEDURE Web.SearchSessions
    @CourseId int = NULL,
    @LanguageCode char(2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(max) = N'SELECT TOP (5) s.SessionId, s.StartDate, s.LanguageCode,
       (SELECT COUNT(*) FROM Enrollment.Enrollment AS e
        WHERE e.SessionId = s.SessionId AND e.CancellationDate IS NULL) AS seats_taken
FROM Course.Session AS s
WHERE s.StartDate > ''20261018''';
    IF @CourseId IS NOT NULL SET @sql += N' AND s.CourseId = @CourseId';
    IF @LanguageCode IS NOT NULL SET @sql += N' AND s.LanguageCode = @LanguageCode';
    SET @sql += N' ORDER BY s.StartDate;';
    EXEC sys.sp_executesql @sql, N'@CourseId int, @LanguageCode char(2)',
         @CourseId = @CourseId, @LanguageCode = @LanguageCode;
END;
GO
GRANT EXECUTE ON SCHEMA::Web TO WebApplication;
GO
-- 2. The dynamic batch is checked with the rights of the caller: Course.Session passes (the
--    role reads the schema Course), Enrollment.Enrollment does not.
EXECUTE AS USER = N'WebSite';
EXEC Web.SearchSessions @LanguageCode = 'EN';
REVERT;
GO
-- 3. The signature: a certificate, a user created from it, the missing right given to that
--    user, and the procedure signed.
CREATE CERTIFICATE WebSigning
    ENCRYPTION BY PASSWORD = N'Web-Signing-2026!lab'
    WITH SUBJECT = N'Signature of the procedures of the website';
CREATE USER WebSigning FROM CERTIFICATE WebSigning;
GRANT SELECT ON Enrollment.Enrollment TO WebSigning;
ADD SIGNATURE TO Web.SearchSessions
    BY CERTIFICATE WebSigning WITH PASSWORD = N'Web-Signing-2026!lab';
SELECT OBJECT_SCHEMA_NAME(cp.major_id) + N'.' + OBJECT_NAME(cp.major_id) AS module_name,
       c.name AS certificate_name, cp.crypt_type_desc
FROM sys.crypt_properties AS cp
JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint;
GO
-- 4. The same call: the rights of WebSigning add up to those of the caller, inside the
--    signed procedure only. Outside, the table still refuses.
EXECUTE AS USER = N'WebSite';
EXEC Web.SearchSessions @LanguageCode = 'EN';
SELECT USER_NAME() AS user_name,
       HAS_PERMS_BY_NAME(N'Enrollment.Enrollment', N'OBJECT', N'SELECT') AS can_read_enrollments;
REVERT;
GO
-- 5. Any change of the code removes the signature, a comment included.
ALTER PROCEDURE Web.SearchSessions
    @CourseId int = NULL,
    @LanguageCode char(2) = NULL
AS
BEGIN
    -- Version 2: a comment, nothing else.
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(max) = N'SELECT TOP (5) s.SessionId, s.StartDate, s.LanguageCode,
       (SELECT COUNT(*) FROM Enrollment.Enrollment AS e
        WHERE e.SessionId = s.SessionId AND e.CancellationDate IS NULL) AS seats_taken
FROM Course.Session AS s
WHERE s.StartDate > ''20261018''';
    IF @CourseId IS NOT NULL SET @sql += N' AND s.CourseId = @CourseId';
    IF @LanguageCode IS NOT NULL SET @sql += N' AND s.LanguageCode = @LanguageCode';
    SET @sql += N' ORDER BY s.StartDate;';
    EXEC sys.sp_executesql @sql, N'@CourseId int, @LanguageCode char(2)',
         @CourseId = @CourseId, @LanguageCode = @LanguageCode;
END;
GO
SELECT COUNT(*) AS signed_modules FROM sys.crypt_properties;
EXECUTE AS USER = N'WebSite';
EXEC Web.SearchSessions @LanguageCode = 'EN';
REVERT;
GO
-- 6. The deployment of a new version signs it again.
ADD SIGNATURE TO Web.SearchSessions
    BY CERTIFICATE WebSigning WITH PASSWORD = N'Web-Signing-2026!lab';
SELECT COUNT(*) AS signed_modules FROM sys.crypt_properties;
GO
