-- Module 13 exercise: solution, parts 1 to 3. Runs on your lab, in one session, after
-- 1-start.sql. Read it after searching. The error was drawn at random, so the script finds
-- it the way you would: it reads the chain, walks the log backups WITH STANDBY on a copy,
-- reads the mark, restores a second copy up to the mark, and repairs the rates from it.
-- It drops its two copies at the end. PachadataTraining_Ex13 is kept for part 4
-- (3-solution-file-loss.sql), which drops it.
USE master;
SET NOCOUNT ON;
GO
-- ========== Part 1: the chain ==========
SELECT b.backup_set_id, b.type, b.first_lsn, b.last_lsn, b.last_valid_restore_time,
       f.physical_device_name
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining_Ex13' AND b.server_name = @@SERVERNAME
ORDER BY b.backup_set_id;
GO

-- ========== Part 2: where is the error? ==========
-- The full backup, then each log backup, WITH STANDBY on a copy, reading the rates after
-- each step. The rates jump in the log backup that contains the error.
DECLARE @undo nvarchar(300) = N'/var/opt/mssql/backup/exercise_13/Ex13_Read_undo.tuf';
RESTORE DATABASE PachadataTraining_Ex13_Read
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_full.bak'
    WITH MOVE N'PachadataTraining'     TO N'/var/opt/mssql/data/PachadataTraining_Ex13_Read.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/PachadataTraining_Ex13_Read_log.ldf',
         STANDBY = @undo;
DECLARE @steps TABLE (step varchar(20), avg_rate decimal(12, 2), last_tick varchar(50));
INSERT INTO @steps
SELECT 'full', (SELECT AVG(DailyRate) FROM PachadataTraining_Ex13_Read.Trainer.Engagement),
       (SELECT TOP (1) Label FROM PachadataTraining_Ex13_Read.dbo.ExClock ORDER BY TickId DESC);
DECLARE @i int = 1, @file nvarchar(300);
WHILE @i <= 3
BEGIN
    SET @file = CONCAT(N'/var/opt/mssql/backup/exercise_13/Ex13_log', @i, N'.trn');
    RESTORE LOG PachadataTraining_Ex13_Read FROM DISK = @file WITH STANDBY = @undo;
    INSERT INTO @steps
    SELECT CONCAT('log ', @i), (SELECT AVG(DailyRate) FROM PachadataTraining_Ex13_Read.Trainer.Engagement),
           (SELECT TOP (1) Label FROM PachadataTraining_Ex13_Read.dbo.ExClock ORDER BY TickId DESC);
    SET @i += 1;
END;
SELECT step, avg_rate, last_tick FROM @steps;
RESTORE DATABASE PachadataTraining_Ex13_Read WITH RECOVERY;
DROP DATABASE PachadataTraining_Ex13_Read;
GO
-- The mark: its name, its description, its time and its LSN.
SELECT TOP (1) database_name, mark_name, description, mark_time, lsn
FROM msdb.dbo.logmarkhistory
WHERE database_name = N'PachadataTraining_Ex13'
ORDER BY mark_time DESC;
GO

-- ========== Part 3: restore next to the database, just before the mark, and repair ==========
-- The full backup, then the log backups up to the one that contains the mark, restored
-- WITH STOPBEFOREMARK. STOPATMARK would replay the marked transaction, error included.
-- The latest mark of that name: logmarkhistory keeps the marks of earlier runs.
DECLARE @mark_lsn numeric(25, 0) = (SELECT TOP (1) lsn FROM msdb.dbo.logmarkhistory
                                    WHERE database_name = N'PachadataTraining_Ex13'
                                      AND mark_name = N'RateIncrease'
                                    ORDER BY mark_time DESC);
RESTORE DATABASE PachadataTraining_Ex13_PIT
    FROM DISK = N'/var/opt/mssql/backup/exercise_13/Ex13_full.bak'
    WITH MOVE N'PachadataTraining'     TO N'/var/opt/mssql/data/PachadataTraining_Ex13_PIT.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/PachadataTraining_Ex13_PIT_log.ldf',
         NORECOVERY;
DECLARE @file nvarchar(300), @last bit;
DECLARE logs CURSOR LOCAL FAST_FORWARD FOR
    SELECT f.physical_device_name, CASE WHEN @mark_lsn BETWEEN b.first_lsn AND b.last_lsn THEN 1 ELSE 0 END
    FROM msdb.dbo.backupset AS b
    JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
    WHERE b.database_name = N'PachadataTraining_Ex13' AND b.server_name = @@SERVERNAME
      AND b.type = 'L' AND b.first_lsn <= @mark_lsn
    ORDER BY b.backup_set_id;
OPEN logs;
FETCH NEXT FROM logs INTO @file, @last;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @last = 1
        RESTORE LOG PachadataTraining_Ex13_PIT FROM DISK = @file
            WITH STOPBEFOREMARK = N'RateIncrease', RECOVERY;
    ELSE
        RESTORE LOG PachadataTraining_Ex13_PIT FROM DISK = @file WITH NORECOVERY;
    FETCH NEXT FROM logs INTO @file, @last;
END;
CLOSE logs;
DEALLOCATE logs;
GO
-- The two databases side by side.
SELECT (SELECT COUNT(*) FROM PachadataTraining_Ex13_PIT.Trainer.Engagement)   AS engagements_in_copy,
       (SELECT MAX(DailyRate) FROM PachadataTraining_Ex13_PIT.Trainer.Engagement) AS max_rate_in_copy,
       (SELECT COUNT(*) FROM PachadataTraining_Ex13.Trainer.Engagement)       AS engagements_in_database,
       (SELECT MAX(DailyRate) FROM PachadataTraining_Ex13.Trainer.Engagement) AS max_rate_in_database;
GO
-- The repair: only the daily rate, only on the rows the copy knows. The engagement entered
-- after the error and the travel expenses changed since keep their values.
UPDATE e
SET DailyRate = c.DailyRate
FROM PachadataTraining_Ex13.Trainer.Engagement AS e
JOIN PachadataTraining_Ex13_PIT.Trainer.Engagement AS c ON c.EngagementId = e.EngagementId
WHERE e.DailyRate <> c.DailyRate;
SELECT @@ROWCOUNT AS repaired_rows;
SELECT COUNT(*) AS engagements, MAX(DailyRate) AS max_rate,
       SUM(CASE WHEN InvoiceNumber = 'EX13-NEW' THEN 1 ELSE 0 END) AS new_engagement_kept
FROM PachadataTraining_Ex13.Trainer.Engagement;
GO
DROP DATABASE PachadataTraining_Ex13_PIT;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13_Read';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13_PIT';
GO
