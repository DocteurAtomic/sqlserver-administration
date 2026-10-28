-- Module 14 exercise, part 2, window A: the planner moves session 17791 to another room, in
-- a transaction that the screen leaves open. Run it in its own window, which stays open.
-- ci: skip (it leaves a transaction open: windows B and C need it)
USE PachadataTraining_Ex14;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE Course.Session SET TrainingRoomId = 12 WHERE SessionId = 17791;
SELECT @@SPID AS session_id, @@TRANCOUNT AS open_transactions;
-- No COMMIT: the window stays open, the session sleeps, and its lock stays.
