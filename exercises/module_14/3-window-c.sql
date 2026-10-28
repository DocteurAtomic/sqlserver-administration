-- Module 14 exercise, part 2, window C: the trainer adds a remark to the same session.
-- ci: skip (it waits for windows A and B)
USE PachadataTraining_Ex14;
SET NOCOUNT ON;
SELECT @@SPID AS session_id;
UPDATE Course.Session SET Remarks = 'Projector needed' WHERE SessionId = 17791;
