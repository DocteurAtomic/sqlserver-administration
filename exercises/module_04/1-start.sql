-- Module 4 exercise: start. Runs on your lab, in one session.
-- 1. Drops MarketingArchive_Ex04, the database you create in part 1, if an earlier try
--    left it.
-- 2. Restores a copy of the database, PachadataTraining_Ex04, and gives it the options of a
--    badly kept database, for part 5. The exercise never writes in PachadataTraining.
-- The solution drops both databases.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'MarketingArchive_Ex04') IS NOT NULL
BEGIN
    ALTER DATABASE MarketingArchive_Ex04 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MarketingArchive_Ex04;
END;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex04';
GO
ALTER DATABASE PachadataTraining_Ex04
    SET AUTO_CLOSE ON, AUTO_SHRINK ON, PAGE_VERIFY TORN_PAGE_DETECTION,
        AUTO_CREATE_STATISTICS OFF, AUTO_UPDATE_STATISTICS OFF;
GO
-- The table you archive: the e-mails of the marketing campaigns, per year.
SELECT YEAR(SendDate) AS send_year, COUNT(*) AS deliveries
FROM PachadataTraining.Marketing.Delivery
WHERE SendDate >= '2023-01-01'
GROUP BY YEAR(SendDate)
ORDER BY send_year;
GO
