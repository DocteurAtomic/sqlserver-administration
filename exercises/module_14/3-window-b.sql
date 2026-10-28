-- Module 14 exercise, part 2, window B: the trainers' portal reads the session.
-- ci: skip (it waits for window A)
USE PachadataTraining_Ex14;
SET NOCOUNT ON;
SELECT @@SPID AS session_id;
SELECT SessionId, TrainingRoomId, StartDate, Remarks
FROM Course.Session
WHERE SessionId = 17791;
