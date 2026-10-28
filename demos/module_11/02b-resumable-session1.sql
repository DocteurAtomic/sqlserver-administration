-- ci: skip (two sessions: run this one first, then 02c-resumable-session2.sql at once)
-- Clip 11.2, end: a resumable online rebuild, paused from a second session.
-- Session 1. Runs on the lab, after 00-setup.sql. The rebuild of pk_Activity (14,452 pages,
-- 7.8 million rows) takes about eight seconds on one processor: start 02c in the second
-- session within two or three seconds. The PAUSE disconnects this session (error 1219).
USE PachadataTraining;
GO
ALTER INDEX pk_Activity ON Elearning.Activity
    REBUILD WITH (ONLINE = ON, RESUMABLE = ON, MAXDOP = 1);
GO
