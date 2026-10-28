-- Module 7, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Restores PachadataTraining as delivered, at level 170: no user, no role and no
--    permission besides the built-in ones.
-- 2. Removes what an earlier run of the module may have left on the instance: the logins
--    and the server role of the clips, the database WebCatalog, and the option
--    contained database authentication, set back to 0 as on the installed lab.
-- 99-cleanup.sql does the same at the end of the module.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'WebCatalog') IS NOT NULL
BEGIN
    ALTER DATABASE WebCatalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WebCatalog;
END;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
IF SUSER_ID(N'PachadataWeb') IS NOT NULL DROP LOGIN PachadataWeb;
IF SUSER_ID(N'PachadataMonitor') IS NOT NULL DROP LOGIN PachadataMonitor;
IF SUSER_ID(N'EventSessionManager') IS NOT NULL DROP SERVER ROLE EventSessionManager;
IF (SELECT value_in_use FROM sys.configurations
    WHERE name = N'contained database authentication') <> 0
BEGIN
    EXEC sys.sp_configure N'contained database authentication', 0;
    RECONFIGURE;
END;
GO
SELECT d.name, d.compatibility_level, d.containment_desc,
       (SELECT COUNT(*) FROM PachadataTraining.sys.database_principals
        WHERE type IN ('S', 'U', 'G', 'R') AND is_fixed_role = 0
          AND name NOT IN (N'dbo', N'guest', N'sys', N'INFORMATION_SCHEMA', N'public'))
           AS users_and_roles
FROM sys.databases AS d
WHERE d.name = N'PachadataTraining';
