#!/usr/bin/env bash
# Clip 14.1: something for the logs to say. Runs from the root of the course repository, in a
# terminal, in about fifteen seconds, after 00-setup.sql:
#   ENGINE=podman ./demos/module_14/01b-events.sh
# For the video: CONTAINER=sqladm-14 ENGINE=podman ./demos/module_14/01b-events.sh
# 1. Two failed connections: a login that does not exist, then sa with a wrong password.
# 2. A message written on purpose in the error log, by RAISERROR ... WITH LOG.
# 3. An Agent job, "Module 14 - Nightly export", whose only step reads a table that does
#    not exist. It is started once and fails. 99-cleanup.sql deletes it.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
# A connection with a given login and password, passed by the environment, never by -P.
as() { $engine exec -i -e SQLCMDPASSWORD="$2" "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U "$1" -C -W -I -l 5 "${@:3}"; }
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

echo "== 1. Two failed connections"
as PachadataExport 'wrong-password' -Q "SELECT 1;"
as sa 'wrong-password' -Q "SELECT 1;"

echo "== 2. A message in the error log"
admin -Q "RAISERROR (N'Module 14: maintenance window opened by the DBA team', 10, 1) WITH LOG;"

echo "== 3. A job that fails"
admin -b -d msdb -Q "SET NOCOUNT ON;
IF EXISTS (SELECT * FROM dbo.sysjobs WHERE name = N'Module 14 - Nightly export')
    EXEC dbo.sp_delete_job @job_name = N'Module 14 - Nightly export';
EXEC dbo.sp_add_job @job_name = N'Module 14 - Nightly export';
EXEC dbo.sp_add_jobstep @job_name = N'Module 14 - Nightly export', @step_name = N'Export invoices',
     @subsystem = N'TSQL', @database_name = N'PachadataTraining',
     @command = N'SELECT * FROM Enrollment.InvoiceExport;';
EXEC dbo.sp_add_jobserver @job_name = N'Module 14 - Nightly export';
EXEC dbo.sp_start_job @job_name = N'Module 14 - Nightly export';"
sleep 8
admin -d msdb -Q "SET NOCOUNT ON;
SELECT h.step_id, h.run_status, h.sql_message_id FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Module 14 - Nightly export' ORDER BY h.instance_id;"
