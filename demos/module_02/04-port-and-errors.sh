#!/usr/bin/env bash
# Clip 2.4: protocols, ports, and the connections that fail. Played for the video on the
# throwaway container sqladm-02:  CONTAINER=sqladm-02 ENGINE=podman ./demos/module_02/04-port-and-errors.sh
# It restarts SQL Server twice (SHUTDOWN, then a start of the container) and takes about
# half a minute. On your lab it runs as is (CONTAINER=sqladmcourse by default) and gives
# the port 1433 back at the end. Several connections fail on purpose.
# 1. mssql-conf moves the instance to the TCP port 1450; a restart applies it.
# 2. A client that still asks for 1433 fails; with the port, it connects.
# 3. Two more failures: no trust in the certificate, a wrong password. The error log says
#    why a login failed, the client does not.
# 4. The port given back to 1433, a second restart.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
sqlcmd() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -W -I -l 5 "$@"; }
restart() {  # $1: the port SQL Server listens on before the restart
    sqlcmd -S localhost,$1 -U sa -C -Q "SHUTDOWN WITH NOWAIT;" || true
    $engine wait $c >/dev/null 2>&1 || true
    $engine start $c >/dev/null
    sleep 8
}

echo "== 1. mssql-conf set network.tcpport 1450, then a restart"
$engine exec $c /opt/mssql/bin/mssql-conf set network.tcpport 1450 2>&1 | grep -v '^Warning'
restart 1433

echo "== 2. A client that asks for the default port"
sqlcmd -S localhost -U sa -C -Q "SELECT 1;"
echo "== The same client, with the port"
sqlcmd -S localhost,1450 -U sa -C -Q "SET NOCOUNT ON;
SELECT ip_address, port, type_desc FROM sys.dm_tcp_listener_states ORDER BY port;
SELECT net_transport, local_tcp_port, encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID;
EXEC sys.xp_readerrorlog 0, 1, N'Server is listening on';"

echo "== 3. Without -C: the client does not trust the self-signed certificate"
sqlcmd -S localhost,1450 -U sa -Q "SELECT 1;"
echo "== A wrong password"
sqlcmd -S localhost,1450 -U sa -P 'Not-the-password-1' -C -Q "SELECT 1;"
echo "== What the error log says"
sqlcmd -S localhost,1450 -U sa -C -Q "EXEC sys.xp_readerrorlog 0, 1, N'Login failed';"

echo "== 4. The port given back, a second restart"
$engine exec $c /opt/mssql/bin/mssql-conf unset network.tcpport 2>&1 | grep -v '^Warning'
restart 1450
sqlcmd -S localhost -U sa -C -Q "SET NOCOUNT ON; SELECT port, type_desc FROM sys.dm_tcp_listener_states WHERE type_desc = N'TSQL' AND ip_address = N'0.0.0.0';"
