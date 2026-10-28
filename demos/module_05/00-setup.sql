-- Module 5, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170.
-- 2. Gives it two defects that the delivered database does not have, and that a DBA finds
--    on a database inherited from another team:
--    - forwarded records in the heap Contact.ProspectUS: the marketing team lengthened the
--      city of one prospect in ten, whose phone number ends in 1 (clip 5.1);
--    - an untrusted foreign key, fk_Enrollment_Session, disabled for a bulk load and
--      enabled again without WITH CHECK (clip 5.2).
-- The module writes in PachadataTraining (rebuild, compression, partitions): the next
-- module's 00-setup.sql restores it.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
-- The marketing update: 99,073 rows get a city 44 characters longer.
UPDATE Contact.ProspectUS
SET City = City + ' (billing address distinct from head office)'
WHERE Phone LIKE '%1';
SELECT @@ROWCOUNT AS prospects_updated;
GO
-- The load that disabled the foreign key, and the re-enable that forgot WITH CHECK.
ALTER TABLE Enrollment.Enrollment NOCHECK CONSTRAINT fk_Enrollment_Session;
ALTER TABLE Enrollment.Enrollment CHECK CONSTRAINT fk_Enrollment_Session;
GO
SELECT name, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE name = N'PachadataTraining';
GO
