-- Module 14 exercise, part 3: the monthly recalculation of the e-learning progress, in one
-- transaction that waits ten minutes before its end. Run it in its own window.
-- ci: skip (it waits ten minutes, until it is killed)
USE PachadataTraining_Ex14;
SET NOCOUNT ON;
SELECT @@SPID AS session_id;
BEGIN TRANSACTION;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds + 1;
WAITFOR DELAY '00:10:00';
ROLLBACK;
