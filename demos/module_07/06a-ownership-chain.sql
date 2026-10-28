-- Clip 7.6: the website enrolls a trainee through a procedure, without any right on the
-- tables. Played for the video on the throwaway container sqladm-07, after 05-permissions.sql:
-- ci: skip (it needs the login of 02a-logins-users.sql)
-- On your lab, run it in one go. It writes one enrollment in PachadataTraining, which the
-- next module's 00-setup.sql removes by restoring the database.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The owners: the schemas Course, Enrollment and Contact belong to dbo, and so do their
--    tables and procedures.
SELECT s.name AS schema_name, USER_NAME(s.principal_id) AS owner_name
FROM sys.schemas AS s
WHERE s.name IN (N'Course', N'Enrollment', N'Contact');
GO
-- 2. The two procedures of the website: the catalog, and the enrollment.
GRANT EXECUTE ON Course.CatalogJson TO WebApplication;
GRANT EXECUTE ON Enrollment.EnrollTrainee TO WebApplication;
GO
-- 3. An open session with free seats and a contact who can enroll, picked as dbo.
DECLARE @session int = (
    SELECT TOP (1) s.SessionId
    FROM Course.Session AS s
    JOIN Course.Course AS c ON c.CourseId = s.CourseId
    JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId
    WHERE s.StatusCode = 'OPEN' AND s.IsInHouse = 0 AND s.StartDate > '20261018'
      AND (SELECT COUNT(*) FROM Enrollment.Enrollment AS e
           WHERE e.SessionId = s.SessionId AND e.CancellationDate IS NULL AND e.WaitingList = 0)
          < CASE WHEN c.MaxAttendees < r.Seats THEN c.MaxAttendees ELSE r.Seats END
    ORDER BY s.SessionId);
DECLARE @contact int = (
    SELECT TOP (1) ct.ContactId
    FROM Contact.Contact AS ct
    LEFT JOIN Contact.Company AS co ON co.CompanyId = ct.CompanyId
    WHERE ct.BirthDate BETWEEN '19700101' AND '19901231'
      AND ISNULL(co.InvoiceBeforeEnrollment, 0) = 0
      AND NOT EXISTS (SELECT * FROM Enrollment.Enrollment AS e WHERE e.ContactId = ct.ContactId)
    ORDER BY ct.ContactId);
SELECT @session AS session_id, @contact AS contact_id;

-- 4. Under the identity of the website: the table refuses, the procedure enrolls.
EXECUTE AS USER = N'WebSite';
BEGIN TRY
    INSERT Enrollment.Enrollment (SessionId, ContactId, Discount, Attended, CreationDate,
                                  AgreementSent, JoiningInstructionsSent, WaitingList)
    VALUES (@session, @contact, 0, 0, '20261018', 0, 0, 0);
END TRY
BEGIN CATCH
    SELECT N'INSERT' AS statement_run, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
EXEC Enrollment.EnrollTrainee @SessionId = @session, @ContactId = @contact;
SELECT HAS_PERMS_BY_NAME(N'Contact.Contact', N'OBJECT', N'SELECT') AS can_read_contacts,
       HAS_PERMS_BY_NAME(N'Enrollment.Enrollment', N'OBJECT', N'INSERT') AS can_insert_enrollments;
REVERT;
GO
