-- Module 9 exercise: starting point. Runs on your lab, in one session. A few seconds.
-- It never writes in PachadataTraining: it restores a copy, PachadataTraining_Ex09, and
-- prepares in it the trainers' portal.
-- The portal is a web application that connects with one account, TrainerPortal, for all
-- the trainers. Each trainer must see only his or her own rates and sessions, and may
-- update the remarks of his or her sessions. The planning team, role Planning, sees all.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex09';
GO
USE PachadataTraining_Ex09;
GO
CREATE USER TrainerPortal WITHOUT LOGIN;
CREATE USER Camille WITHOUT LOGIN;
CREATE ROLE Planning AUTHORIZATION dbo;
ALTER ROLE Planning ADD MEMBER Camille;
GRANT SELECT ON Trainer.TrainerRate TO TrainerPortal;
GRANT SELECT, UPDATE ON Course.Session TO TrainerPortal;
GRANT SELECT ON Trainer.TrainerRate TO Planning;
GRANT SELECT ON Course.Session TO Planning;
GO
SELECT TrainerId,
       (SELECT COUNT(*) FROM Trainer.TrainerRate AS r WHERE r.TrainerId = t.TrainerId) AS rates,
       (SELECT COUNT(*) FROM Course.Session AS s WHERE s.TrainerId = t.TrainerId) AS sessions
FROM Trainer.Trainer AS t
WHERE TrainerId IN (1, 2);
