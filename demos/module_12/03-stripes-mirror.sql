-- Clip 12.3: a backup on several files, and its mirror. Runs on the lab, in one session,
-- after 02-backup-chain.sql.
-- ci: skip (parts 1 and 4 end on an expected error, which stops sqlcmd -b)
-- Run it part by part. Every backup here is a test: COPY_ONLY, so the differentials keep
-- their base. On the lab, the four files are on the same disk as the database: the mirror
-- protects from nothing here, on a server it goes to another volume.
USE master;
SET NOCOUNT ON;
GO
-- 0. Where a BACKUP without a path writes: the default backup folder of the instance, and
--    the folders of the data and log files.
SELECT SERVERPROPERTY('InstanceDefaultBackupPath') AS backup_path,
       SERVERPROPERTY('InstanceDefaultDataPath') AS data_path,
       SERVERPROPERTY('InstanceDefaultLogPath') AS log_path;
GO
-- 1. Two files in TO (stripes), mirrored on two others, without FORMAT: refused (3215).
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak',
       DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s2.bak'
    MIRROR TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_m1.bak',
              DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_m2.bak'
    WITH COPY_ONLY, CHECKSUM;
GO
-- 2. The same with FORMAT.
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak',
       DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s2.bak'
    MIRROR TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_m1.bak',
              DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_m2.bak'
    WITH COPY_ONLY, CHECKSUM, FORMAT;
SELECT f.family_sequence_number, f.mirror,
       RIGHT(f.physical_device_name, CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1) AS file_name
FROM msdb.dbo.backupmediafamily AS f
WHERE f.media_set_id = (SELECT MAX(media_set_id) FROM msdb.dbo.backupset
                        WHERE database_name = N'PachadataTraining')
ORDER BY f.mirror, f.family_sequence_number;
GO
-- 3. The first file of the mirror stands in for the first file of TO.
RESTORE VERIFYONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_m1.bak',
         DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s2.bak'
    WITH CHECKSUM;
GO
-- 4. One file of the stripes alone: refused (3132).
RESTORE VERIFYONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak'
    WITH CHECKSUM;
GO
-- 5. What the files contain: the media set, the backup sets, the database files.
RESTORE LABELONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak';
RESTORE HEADERONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak',
         DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s2.bak';
RESTORE FILELISTONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s1.bak',
         DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_s2.bak';
GO
