#!/usr/bin/env bash
# Clip 14.1: make the two settings of the clip survive a restart, with mssql-conf. Runs from
# the root of the course repository, in a terminal, in about a minute:
#   ENGINE=podman ./demos/module_14/01d-startup-settings.sh        (sets them)
#   ENGINE=podman ./demos/module_14/01d-startup-settings.sh off    (puts the defaults back)
# For the video: CONTAINER=sqladm-14 ENGINE=podman ./demos/module_14/01d-startup-settings.sh
# It restarts SQL Server: SHUTDOWN, then a start of the container, never a stop of the
# container, which SQL Server does not survive cleanly.
# 1. Thirty archives of the error log instead of six (errorlog.numerrorlogs).
# 2. Trace flag 3226 at startup (traceflag 3226 on).
# 3. The restart, then the proof: the startup line of the error log, the trace flag, and
#    /var/opt/mssql/mssql.conf, where mssql-conf writes.
# On Windows, the same two settings are in SSMS (SQL Server Logs, Configure) and in
# SQL Server Configuration Manager (startup parameter -T3226).
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

if [ "${1:-}" = off ]; then
    $engine exec "$c" /opt/mssql/bin/mssql-conf unset errorlog.numerrorlogs
    $engine exec "$c" /opt/mssql/bin/mssql-conf traceflag 3226 off
else
    echo "== 1 and 2. The two settings"
    $engine exec "$c" /opt/mssql/bin/mssql-conf set errorlog.numerrorlogs 30
    $engine exec "$c" /opt/mssql/bin/mssql-conf traceflag 3226 on
fi
$engine exec "$c" cat /var/opt/mssql/mssql.conf

echo "== 3. Restart"
admin -Q "SHUTDOWN;" || true
sleep 5
$engine start "$c" >/dev/null
for i in $(seq 1 60); do
    admin -l 2 -Q "SELECT 1" >/dev/null 2>&1 && break
    sleep 2
done
admin -Q "SET NOCOUNT ON;
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
EXEC sys.sp_readerrorlog 0, 1, N'Registry startup parameters';
DBCC TRACESTATUS (-1);
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
     N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs';"
