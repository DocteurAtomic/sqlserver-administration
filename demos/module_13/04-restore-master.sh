#!/usr/bin/env bash
# ci: skip (it creates and removes a throwaway container)
# Clip 13.4: restoring msdb and master. Runs on your machine, from the root of the repository,
# never against the lab: it creates its own container, sqladm-master by default, and removes
# it at the end. It takes about three minutes.
#   ./demos/module_13/04-restore-master.sh                  (with Podman: ENGINE=podman ...)
#   KEEP=1 ./demos/module_13/04-restore-master.sh           keeps the container at the end
# In a container, sqlservr is process 1: stopping it stops the container, and it cannot be
# started again in single-user mode. So the container starts on "sleep infinity", and the
# script starts sqlservr by hand, the way systemctl and "sqlservr -m" work on a Linux server.
# 1. Backs up msdb and master, then creates after the backups a login, a database and an
#    Agent job, and deletes a job that existed before them.
# 2. Restores msdb with REPLACE, the database in SINGLE_USER: the deleted job comes back.
# 3. Tries to restore master normally (error 3108), stops the engine, starts it with
#    -m"SQLCMD", restores master, starts it normally: the login and the database created after
#    the backup are gone, the files of the database are still there, and it is attached again.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladm-master}
pw='Course-2026!lab'
image=mcr.microsoft.com/mssql/server:2025-CU7-ubuntu-24.04
q() { echo "> $*" | cut -c1-150; $engine exec -e SQLCMDPASSWORD="$pw" $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -W -Q "SET NOCOUNT ON; $*" || true; }
start() {  # starts sqlservr in the background, with its arguments, and waits for it
    $engine exec -d $c /opt/mssql/bin/sqlservr "$@" >/dev/null
    for _ in $(seq 60); do
        if $engine exec -e SQLCMDPASSWORD="$pw" $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -l 2 -Q "SELECT 1" >/dev/null 2>&1; then return; fi
        sleep 2
    done
    echo "sqlservr did not answer" >&2; exit 1
}
running() { $engine exec $c bash -c 'grep -lx sqlservr /proc/[0-9]*/comm' >/dev/null 2>&1; }
stopped() {  # waits until sqlservr has exited
    for _ in $(seq 60); do
        running || return 0
        sleep 1
    done
}

echo "== The container, on sleep infinity, and the engine started by hand"
$engine run -d --name $c --memory 4g --cpus 2 -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
    -e MSSQL_AGENT_ENABLED=true -e MSSQL_SA_PASSWORD="$pw" \
    --entrypoint /bin/sleep $image infinity >/dev/null
$engine exec -u 0 $c bash -c 'mkdir -p /var/opt/mssql/backup && chown mssql /var/opt/mssql/backup'
start
# The Agent refuses job changes while it starts (error 14258): wait until it runs.
for _ in $(seq 60); do
    $engine exec -e SQLCMDPASSWORD="$pw" $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -Q "EXEC msdb.dbo.sp_is_sqlagent_starting;" >/dev/null 2>&1 && break
    sleep 2
done
q "SELECT @@VERSION AS version;"

echo "== 1. The backups, then what happens after them"
q "EXEC msdb.dbo.sp_add_job @job_name = N'Module 13 - Kept job'; EXEC msdb.dbo.sp_add_jobstep @job_name = N'Module 13 - Kept job', @step_name = N'Select', @subsystem = N'TSQL', @command = N'SELECT 1;'; EXEC msdb.dbo.sp_add_jobserver @job_name = N'Module 13 - Kept job';"
q "BACKUP DATABASE msdb TO DISK = N'/var/opt/mssql/backup/msdb.bak' WITH INIT, FORMAT, CHECKSUM;"
q "BACKUP DATABASE master TO DISK = N'/var/opt/mssql/backup/master.bak' WITH INIT, FORMAT, CHECKSUM;"
q "CREATE LOGIN AfterBackup13 WITH PASSWORD = N'After!13!Backup', CHECK_POLICY = OFF; CREATE DATABASE AfterBackup13; EXEC msdb.dbo.sp_delete_job @job_name = N'Module 13 - Kept job'; EXEC msdb.dbo.sp_add_job @job_name = N'Module 13 - New job';"
q "SELECT name FROM sys.server_principals WHERE name = N'AfterBackup13'; SELECT name FROM sys.databases WHERE database_id > 4; SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Module 13%'; SELECT COUNT(*) AS backups_in_history FROM msdb.dbo.backupset;"

echo "== 2. msdb: SINGLE_USER, then RESTORE ... WITH REPLACE in the same session"
q "ALTER DATABASE msdb SET SINGLE_USER WITH ROLLBACK IMMEDIATE; RESTORE DATABASE msdb FROM DISK = N'/var/opt/mssql/backup/msdb.bak' WITH REPLACE; ALTER DATABASE msdb SET MULTI_USER;"
q "SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Module 13%'; SELECT COUNT(*) AS backups_in_history FROM msdb.dbo.backupset;"
echo "== The Agent after the restore of msdb: the job is started, its history read 10 seconds later"
q "EXEC msdb.dbo.sp_start_job @job_name = N'Module 13 - Kept job';"
sleep 10
q "SELECT COUNT(*) AS job_runs FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id WHERE j.name = N'Module 13 - Kept job';"

echo "== 3. master: first in normal mode"
q "RESTORE DATABASE master FROM DISK = N'/var/opt/mssql/backup/master.bak' WITH REPLACE;"
echo "== The engine stopped, then started in single-user mode, for sqlcmd only"
q "SHUTDOWN;"
stopped
start -mSQLCMD
q "SELECT SERVERPROPERTY('IsSingleUser') AS is_single_user;"
q "RESTORE DATABASE master FROM DISK = N'/var/opt/mssql/backup/master.bak' WITH REPLACE;"
stopped
if running; then echo "sqlservr still running"; else echo "sqlservr stopped by the restore of master"; fi
echo "== The engine started normally"
start
q "SELECT name FROM sys.server_principals WHERE name = N'AfterBackup13'; SELECT name FROM sys.databases WHERE database_id > 4;"
$engine exec $c ls -l /var/opt/mssql/data/ | grep AfterBackup13
q "CREATE DATABASE AfterBackup13 ON (FILENAME = N'/var/opt/mssql/data/AfterBackup13.mdf'), (FILENAME = N'/var/opt/mssql/data/AfterBackup13_log.ldf') FOR ATTACH; SELECT name, state_desc FROM sys.databases WHERE name = N'AfterBackup13';"
echo "== The Agent after the restart: the same job, started again"
sleep 15
q "EXEC msdb.dbo.sp_start_job @job_name = N'Module 13 - Kept job';"
sleep 10
q "SELECT COUNT(*) AS job_runs FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id WHERE j.name = N'Module 13 - Kept job';"

if [ "${KEEP:-0}" != 1 ]; then
    echo "== The container goes"
    $engine rm -f $c >/dev/null
fi
