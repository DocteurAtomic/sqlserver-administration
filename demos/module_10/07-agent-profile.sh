#!/usr/bin/env bash
# Clip 10.3: the Agent's mail profile, on Linux. Runs from the root of the course repository,
# in a terminal, in about a minute, after 06-operator.sql:
#   ENGINE=podman ./demos/module_10/07-agent-profile.sh
# For the video: CONTAINER=sqladm-10 ENGINE=podman ./demos/module_10/07-agent-profile.sh
# 1. What the Agent's settings say of its mail profile: nothing yet. On Windows they live in
#    the registry; on Linux, xp_instance_regread reads them from mssql.conf.
# 2. mssql-conf writes the profile in /var/opt/mssql/mssql.conf, section [sqlagent].
# 3. A restart of SQL Server, which reads the file: SHUTDOWN, then the container started
#    again. Never docker stop on this image, which ignores SIGTERM and kills SQL Server.
# 4. The settings again, and the job of 06-operator.sql started again: its notification is queued.
# On Windows, the same setting is on the page Alert System of the Agent's properties, then a
# restart of the Agent.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
sql() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }
profile="PachadataMail"

echo "== 1. The Agent's mail settings"
agent_reg() {
    sql -Q "SET NOCOUNT ON;
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\\Microsoft\\MSSQLServer\\SQLServerAgent', N'UseDatabaseMail';
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\\Microsoft\\MSSQLServer\\SQLServerAgent', N'DatabaseMailProfile';"
}
agent_reg

echo "== 2. mssql-conf"
$engine exec "$c" /opt/mssql/bin/mssql-conf set sqlagent.databasemailprofile "$profile"
$engine exec "$c" sh -c 'sed -n "/^\[sqlagent\]/,/^\[/p" /var/opt/mssql/mssql.conf'

echo "== 3. The restart"
sql -Q "SHUTDOWN WITH NOWAIT;" || true
until [ "$($engine inspect -f '{{.State.Running}}' "$c")" = false ]; do sleep 1; done
$engine start "$c" >/dev/null
until sql -Q "SELECT 1" >/dev/null 2>&1; do sleep 2; done
sleep 10   # the Agent starts a few seconds after the engine

echo "== 4. The settings again, and the job started again"
agent_reg
sql -d msdb -Q "SET NOCOUNT ON;
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Failing test';
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Failing test' AND h.step_id = 0 AND h.instance_id > @last)
    WAITFOR DELAY '00:00:01';
WAITFOR DELAY '00:00:10';
SELECT TOP (1) h.message FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Failing test' AND h.step_id = 0 ORDER BY h.instance_id DESC;
SELECT TOP (1) mailitem_id, recipients, subject, sent_status FROM dbo.sysmail_allitems ORDER BY mailitem_id DESC;"
