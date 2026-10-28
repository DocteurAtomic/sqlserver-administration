-- Module 13 exercise: start. Runs on your lab, in one session, alone. It takes about a
-- minute.
-- Restores a copy of the database, PachadataTraining_Ex13, which stands for the trainers'
-- billing, puts it in FULL and takes a chain of backups in /var/opt/mssql/backup/exercise_13:
-- a full backup and three log backups. Between two of them, at a moment drawn at random,
-- a botched update sets the daily rate of every engagement to ten percent of its value
-- instead of raising it by ten percent, in a marked transaction. Work goes on after the
-- error: a new engagement is entered, then more log backups. A table dbo.ExClock gets one row before each step.
-- The exercise never writes in PachadataTraining. The solution deletes what it creates.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex13';
ALTER DATABASE PachadataTraining_Ex13 SET RECOVERY FULL;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_13';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'trn', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13';
GO
USE PachadataTraining_Ex13;
CREATE TABLE dbo.ExClock (
    TickId int IDENTITY PRIMARY KEY,
    Label  varchar(50) NOT NULL,
    At     datetime2(3) NOT NULL DEFAULT SYSDATETIME()
);
GO
USE master;
DECLARE @error_after int = 1 + CAST(RAND(CHECKSUM(NEWID())) * 2 AS int);  -- after log 1 or log 2
DECLARE @i int = 1, @file nvarchar(300);

INSERT INTO PachadataTraining_Ex13.dbo.ExClock (Label) VALUES ('before full');
BACKUP DATABASE PachadataTraining_Ex13
    TO DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_full.bak' WITH INIT, FORMAT, CHECKSUM;

WHILE @i <= 3
BEGIN
    WAITFOR DELAY '00:00:05';
    -- Ordinary work: one more travel expense on ten engagements.
    UPDATE TOP (10) PachadataTraining_Ex13.Trainer.Engagement
    SET TravelExpenses = TravelExpenses + 1
    WHERE EngagementId % 100 = @i;
    IF @i = @error_after + 1
    BEGIN
        -- The error: "* 1.10" typed as "* 0.10", without WHERE.
        BEGIN TRANSACTION RateIncrease WITH MARK N'Daily rates of the trainers, + 10 %';
            UPDATE PachadataTraining_Ex13.Trainer.Engagement SET DailyRate = DailyRate * 0.10;
        COMMIT;
        WAITFOR DELAY '00:00:02';
        -- Work goes on: a new engagement is entered after the error, on a session that had
        -- none (one engagement per session).
        INSERT INTO PachadataTraining_Ex13.Trainer.Engagement
               (SessionId, TrainerId, TrainerCompanyId, InvoiceNumber, InvoiceDate, DayCount, DailyRate, TravelExpenses)
        SELECT TOP (1) s.SessionId, e.TrainerId, e.TrainerCompanyId, 'EX13-NEW', '20261028', 2, 650, 0
        FROM PachadataTraining_Ex13.Course.Session AS s
        CROSS JOIN (SELECT TOP (1) TrainerId, TrainerCompanyId
                    FROM PachadataTraining_Ex13.Trainer.Engagement ORDER BY EngagementId DESC) AS e
        WHERE NOT EXISTS (SELECT * FROM PachadataTraining_Ex13.Trainer.Engagement AS x
                          WHERE x.SessionId = s.SessionId)
        ORDER BY s.SessionId DESC;
    END;
    SET @file = CONCAT(N'/var/opt/mssql/backup/exercise_13/Ex13_log', @i, N'.trn');
    INSERT INTO PachadataTraining_Ex13.dbo.ExClock (Label) VALUES (CONCAT('before log ', @i));
    BACKUP LOG PachadataTraining_Ex13 TO DISK = @file WITH INIT, FORMAT, CHECKSUM;
    SET @i += 1;
END;
GO
-- What the database looks like now. The error is in the chain; where is up to you to find.
SELECT d.name, d.recovery_model_desc FROM sys.databases AS d WHERE d.name = N'PachadataTraining_Ex13';
SELECT COUNT(*) AS engagements, MIN(DailyRate) AS min_rate, MAX(DailyRate) AS max_rate
FROM PachadataTraining_Ex13.Trainer.Engagement;
GO
