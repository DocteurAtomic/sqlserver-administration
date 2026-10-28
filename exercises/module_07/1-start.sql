-- Module 7 exercise: start. Runs on your lab, in one session, in a few seconds.
-- Creates the database of the e-learning platform, PachadataElearning_Ex07, from
-- PachadataTraining, which it only reads:
--   Elearning.Module and Elearning.Progress, copies of the tables of PachadataTraining;
--   Contact.Trainee, the trainees who have a progress, with their birth date;
--   Elearning.RecordProgress, the procedure that the platform calls to record a progress.
-- It also creates the folder of the exercise's backup, /var/opt/mssql/backup/exercise_07.
-- The exercise never writes in PachadataTraining. The solution deletes what it creates.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataElearning_Ex07_Test') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataElearning_Ex07_Test SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataElearning_Ex07_Test;
END;
IF DB_ID(N'PachadataElearning_Ex07') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataElearning_Ex07 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataElearning_Ex07;
END;
IF SUSER_ID(N'PachadataElearning') IS NOT NULL DROP LOGIN PachadataElearning;
GO
CREATE DATABASE PachadataElearning_Ex07;
ALTER DATABASE PachadataElearning_Ex07 SET RECOVERY SIMPLE;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_07';
GO
USE PachadataElearning_Ex07;
GO
CREATE SCHEMA Elearning AUTHORIZATION dbo;
GO
CREATE SCHEMA Contact AUTHORIZATION dbo;
GO
SELECT ModuleId, CourseId, Position, Title, Kind, DurationMinutes, StepCount
INTO Elearning.Module
FROM PachadataTraining.Elearning.Module;
ALTER TABLE Elearning.Module ADD CONSTRAINT PK_Module PRIMARY KEY (ModuleId);

SELECT p.EnrollmentId, e.ContactId, p.ModuleId, p.Status, p.ProgressPercent, p.BestScore,
       p.TimeSpentSeconds, p.LastActivity
INTO Elearning.Progress
FROM PachadataTraining.Elearning.Progress AS p
JOIN PachadataTraining.Enrollment.Enrollment AS e ON e.EnrollmentId = p.EnrollmentId;
ALTER TABLE Elearning.Progress ADD CONSTRAINT PK_Progress PRIMARY KEY (EnrollmentId, ModuleId);

SELECT c.ContactId, c.FirstName, c.LastName, c.Email, c.BirthDate
INTO Contact.Trainee
FROM PachadataTraining.Contact.Contact AS c
WHERE c.ContactId IN (SELECT ContactId FROM Elearning.Progress);
ALTER TABLE Contact.Trainee ADD CONSTRAINT PK_Trainee PRIMARY KEY (ContactId);
GO
CREATE PROCEDURE Elearning.RecordProgress
    @EnrollmentId int,
    @ModuleId int,
    @ProgressPercent tinyint,
    @SecondsSpent int
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Elearning.Progress
    SET ProgressPercent = CASE WHEN @ProgressPercent > ProgressPercent
                               THEN @ProgressPercent ELSE ProgressPercent END,
        TimeSpentSeconds = TimeSpentSeconds + @SecondsSpent,
        Status = CASE WHEN @ProgressPercent >= 100 THEN 'D' ELSE Status END,
        LastActivity = SYSDATETIME()
    WHERE EnrollmentId = @EnrollmentId AND ModuleId = @ModuleId;
    SELECT EnrollmentId, ModuleId, Status, ProgressPercent, TimeSpentSeconds
    FROM Elearning.Progress
    WHERE EnrollmentId = @EnrollmentId AND ModuleId = @ModuleId;
END;
GO
SELECT N'Elearning.Module' AS table_name, COUNT(*) AS row_count FROM Elearning.Module
UNION ALL SELECT N'Elearning.Progress', COUNT(*) FROM Elearning.Progress
UNION ALL SELECT N'Contact.Trainee', COUNT(*) FROM Contact.Trainee;
GO
