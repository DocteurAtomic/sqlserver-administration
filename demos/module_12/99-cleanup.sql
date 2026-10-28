-- Module 12, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Removes the two schedules of 05b-schedule-jobs.sql and gives the two backup jobs back
--    their command as setup/install-ola.sh created it. DBA and its jobs belong to the lab.
-- 2. Deletes the backup files (.bak, .trn) under /var/opt/mssql/backup/module_12, in every
--    subfolder. T-SQL deletes neither folders nor other files: the empty folders and the two
--    certificate files go with
--      docker exec sqladmcourse rm -rf /var/opt/mssql/backup/module_12
-- 3. Deletes the backup history of PachadataTraining and DBA in msdb.
-- 4. Drops the certificate of 04b-encrypted-backup.sql, and the database master key of
--    master when no other certificate or asymmetric key of master uses it.
-- PachadataTraining itself is restored by the next module's 00-setup.sql.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The schedules of the module, and the commands of the two jobs as installed.
IF EXISTS (SELECT * FROM dbo.sysschedules WHERE name = N'Every night at 1:00')
    EXEC dbo.sp_delete_schedule @schedule_name = N'Every night at 1:00', @force_delete = 1;
IF EXISTS (SELECT * FROM dbo.sysschedules WHERE name = N'Every 15 minutes')
    EXEC dbo.sp_delete_schedule @schedule_name = N'Every 15 minutes', @force_delete = 1;
EXEC dbo.sp_update_jobstep
    @job_name = N'DatabaseBackup - USER_DATABASES - FULL', @step_id = 1,
    @command = N'EXECUTE [dbo].[DatabaseBackup]
@Databases = ''USER_DATABASES'',
@Directory = N''/var/opt/mssql/backup'',
@BackupType = ''FULL'',
@Verify = ''Y'',
@CleanupTime = NULL,
@Checksum = ''Y'',
@LogToTable = ''Y''';
EXEC dbo.sp_update_jobstep
    @job_name = N'DatabaseBackup - USER_DATABASES - LOG', @step_id = 1,
    @command = N'EXECUTE [dbo].[DatabaseBackup]
@Databases = ''USER_DATABASES'',
@Directory = N''/var/opt/mssql/backup'',
@BackupType = ''LOG'',
@Verify = ''Y'',
@CleanupTime = NULL,
@Checksum = ''Y'',
@LogToTable = ''Y''';
GO
-- 2. The backup files, folder by folder, before the certificate: xp_delete_file reads the
--    header of each file, and the header of an encrypted backup needs the certificate.
--    xp_dirtree lists the tree depth first: the path of a folder is the path of the last
--    folder listed one level up, plus its name.
DECLARE @root nvarchar(400) = N'/var/opt/mssql/backup/module_12';
DECLARE @tree TABLE (id int IDENTITY PRIMARY KEY, subdirectory nvarchar(400), depth int, is_file bit);
DECLARE @folders TABLE (id int PRIMARY KEY, depth int, path nvarchar(4000));
EXEC master.dbo.xp_create_subdir @root;
INSERT INTO @tree (subdirectory, depth, is_file) EXEC master.sys.xp_dirtree @root, 0, 1;
INSERT INTO @folders VALUES (0, 0, @root);
INSERT INTO @folders (id, depth, path)
SELECT t.id, t.depth, NULL FROM @tree AS t WHERE t.is_file = 0;
DECLARE @id int = 0, @depth int, @path nvarchar(4000);
WHILE 1 = 1
BEGIN
    SELECT TOP (1) @id = id, @depth = depth FROM @folders WHERE id > @id ORDER BY id;
    IF @@ROWCOUNT = 0 BREAK;
    UPDATE f SET path = (SELECT TOP (1) p.path FROM @folders AS p
                         WHERE p.depth = @depth - 1 AND p.id < @id ORDER BY p.id DESC)
                        + N'/' + t.subdirectory
    FROM @folders AS f JOIN @tree AS t ON t.id = f.id
    WHERE f.id = @id;
END;
DECLARE folders CURSOR LOCAL FAST_FORWARD FOR SELECT path FROM @folders;
OPEN folders;
FETCH NEXT FROM folders INTO @path;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.sys.xp_delete_file 0, @path, N'bak', N'2100-01-01', 0;
    EXEC master.sys.xp_delete_file 0, @path, N'trn', N'2100-01-01', 0;
    FETCH NEXT FROM folders INTO @path;
END;
CLOSE folders;
DEALLOCATE folders;
GO
-- 3. The backup history.
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'DBA';
GO
-- 4. The certificate, and the master key when nothing else needs it.
IF CERT_ID(N'BackupCert12') IS NOT NULL
    DROP CERTIFICATE BackupCert12;
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
GO
-- What is left: folders and the certificate files, no backup.
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_12', 0, 1;
SELECT j.name, sc.name AS schedule_name FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id;
SELECT name FROM sys.certificates WHERE name NOT LIKE N'##%';
SELECT name FROM sys.databases WHERE database_id > 4;
GO
