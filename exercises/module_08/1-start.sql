-- Module 8 exercise: start. Runs on your lab, in one session. It takes a few seconds.
-- Creates the database PachadataContacts_Ex08, which stands for the contact file of the sales
-- team: a copy of the contacts of PachadataTraining (which it only reads), with their e-mail
-- address, and a user MailingTool, without a login, which reads the table. It also creates the
-- folder of the exercise's files, /var/opt/mssql/backup/exercise_08. 5-cleanup.sql removes
-- what the exercise creates.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataContacts_Ex08') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataContacts_Ex08 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataContacts_Ex08;
END;
GO
CREATE DATABASE PachadataContacts_Ex08;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_08';
GO
USE PachadataContacts_Ex08;
GO
CREATE SCHEMA Contact AUTHORIZATION dbo;
GO
SELECT ContactId, LastName, FirstName, Email
INTO Contact.Contact
FROM PachadataTraining.Contact.Contact;
ALTER TABLE Contact.Contact ADD CONSTRAINT PK_Contact PRIMARY KEY (ContactId);
GO
CREATE USER MailingTool WITHOUT LOGIN;
GRANT SELECT ON Contact.Contact TO MailingTool;
GO
SELECT COUNT(*) AS contacts, COUNT(Email) AS with_email,
       MAX(LEN(Email)) AS longest_email
FROM Contact.Contact;
SELECT TOP (3) ContactId, LastName, Email FROM Contact.Contact ORDER BY ContactId;
GO
