#!/usr/bin/env bash
# Clip 2.3: SQL Server on Linux and in a container. Played for the video on the throwaway
# container sqladm-02:  CONTAINER=sqladm-02 ENGINE=podman ./demos/module_02/03-memory-limit.sh
# It restarts SQL Server twice (SHUTDOWN, then a start of the container) and takes about
# half a minute. On your lab it runs as is (CONTAINER=sqladmcourse by default) and leaves
# the instance as it found it: the setting is removed at the end.
# 1. How the container was configured: environment variables, no mssql.conf.
# 2. mssql-conf limits the memory of the process to 2,560 MB; a restart applies it.
# 3. The setting removed, a second restart, back to 80 % of the container.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
sql() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }
memory() { sql -Q "SET NOCOUNT ON; SELECT physical_memory_kb / 1024 AS physical_memory_mb, committed_target_kb / 1024 AS target_mb FROM sys.dm_os_sys_info;"; }
restart() {  # SHUTDOWN stops SQL Server, and the container with it; start brings both back.
    sql -Q "SHUTDOWN WITH NOWAIT;" || true
    $engine wait $c >/dev/null 2>&1 || true
    $engine start $c >/dev/null
    for i in $(seq 1 60); do sql -l 2 -Q "SELECT 1;" >/dev/null 2>&1 && return; sleep 1; done
    echo "SQL Server did not come back" >&2; exit 1
}

echo "== 1. The environment variables of the container (passwords hidden)"
$engine inspect $c --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^MSSQL_' | grep -v PASSWORD
echo "== mssql.conf"
$engine exec $c cat /var/opt/mssql/mssql.conf 2>&1 || true
echo "== The memory the process sees, before"
memory

echo "== 2. mssql-conf set memory.memorylimitmb 2560, then a restart"
$engine exec $c /opt/mssql/bin/mssql-conf set memory.memorylimitmb 2560 2>&1 | grep -v '^Warning'
$engine exec $c cat /var/opt/mssql/mssql.conf
restart
memory
sql -Q "EXEC sys.xp_readerrorlog 0, 1, N'of RAM';"

echo "== 3. The setting removed, a second restart"
$engine exec $c /opt/mssql/bin/mssql-conf unset memory.memorylimitmb 2>&1 | grep -v '^Warning'
restart
memory
