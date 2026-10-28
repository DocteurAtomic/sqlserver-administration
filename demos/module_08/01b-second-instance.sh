#!/usr/bin/env bash
# ci: skip (it creates, changes and removes a throwaway container)
# Clips 8.1 and 8.5: the second instance of the module, sqladm-08b. Runs on your machine, from
# the root of the repository, never against the lab: the lab only lends its backup folder.
#   ./demos/module_08/01b-second-instance.sh create          a fresh SQL Server 2025, port 14434
#   ./demos/module_08/01b-second-instance.sh tls             a TLS certificate, and a connection
#                                                             in TDS 8.0 (Encrypt=Strict)
#   ./demos/module_08/01b-second-instance.sh copy [folder]   copies /var/opt/mssql/backup/<folder>
#                                                             of the lab (module_08 by default)
#   ./demos/module_08/01b-second-instance.sh restart         stops and starts SQL Server
#   ./demos/module_08/01b-second-instance.sh remove          removes the container
# With Podman: ENGINE=podman ./demos/module_08/01b-second-instance.sh create
# SOURCE names the lab container (sqladmcourse), TARGET the second one (sqladm-08b), MEMORY
# its memory limit (2g). The password is the lab password of the README. In a container,
# SQL Server is process 1: SHUTDOWN stops the container, and "start" brings it back.
set -euo pipefail
engine=${ENGINE:-docker}
c=${TARGET:-sqladm-08b}
src=${SOURCE:-sqladmcourse}
pw=${MSSQL_SA_PASSWORD:-Course-2026!lab}
image=mcr.microsoft.com/mssql/server:2025-CU7-ubuntu-24.04
sq() { $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -U sa -I -W "$@"; }
wait_sql() { until sq -S localhost -C -Q "SELECT 1" >/dev/null 2>&1; do sleep 2; done; }
restart() {
    sq -S localhost -C -Q "SHUTDOWN;" >/dev/null 2>&1 || true
    until [ "$($engine inspect -f '{{.State.Running}}' "$c")" = false ]; do sleep 1; done
    $engine start "$c" >/dev/null
    wait_sql
}
tds='SET NOCOUNT ON; SELECT encrypt_option, CONVERT(varbinary(4), protocol_version) AS tds_version FROM sys.dm_exec_connections WHERE session_id = @@SPID;'

case "${1:-}" in
create)
    echo "== a fresh SQL Server 2025, same image as the lab, host name $c"
    $engine run -d --name "$c" --hostname "$c" --memory "${MEMORY:-2g}" --cpus 2 \
        -p "127.0.0.1:${PORT:-14434}:1433" -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
        -e "MSSQL_SA_PASSWORD=$pw" -e "SQLCMDPASSWORD=$pw" "$image" >/dev/null
    wait_sql
    $engine exec -u 0 "$c" bash -c 'mkdir -p /var/opt/mssql/backup && chown mssql /var/opt/mssql/backup'
    sq -S localhost -C -Q "SET NOCOUNT ON; SELECT @@SERVERNAME AS server_name, SERVERPROPERTY('ProductVersion') AS version;"
    ;;
tls)
    echo "== Encrypt=Strict with the certificate SQL Server generated at startup"
    sq -S localhost -C -N s -Q "$tds" || true
    echo "== a certificate for the name $c, for server authentication, and its key"
    $engine exec "$c" openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
        -subj "/CN=$c" -addext "extendedKeyUsage=serverAuth" -addext "subjectAltName=DNS:$c" \
        -keyout /var/opt/mssql/secrets/mssql.key -out /var/opt/mssql/secrets/mssql.pem 2>/dev/null
    $engine exec "$c" chmod 600 /var/opt/mssql/secrets/mssql.key /var/opt/mssql/secrets/mssql.pem
    $engine exec "$c" openssl x509 -in /var/opt/mssql/secrets/mssql.pem -noout -subject -enddate
    $engine exec "$c" /opt/mssql/bin/mssql-conf set network.tlscert /var/opt/mssql/secrets/mssql.pem
    $engine exec "$c" /opt/mssql/bin/mssql-conf set network.tlskey /var/opt/mssql/secrets/mssql.key
    $engine exec "$c" cat /var/opt/mssql/mssql.conf
    echo "== restart: the certificate is read at startup"
    restart
    echo "== Encrypt=Strict, certificate installed: -C (TrustServerCertificate) does not count"
    sq -S localhost -C -N s -Q "$tds" || true
    echo "== Encrypt=Strict, the client given the server certificate (-J): TDS 8.0"
    sq -S localhost -N s -J /var/opt/mssql/secrets/mssql.pem -Q "$tds"
    echo "== Encrypt=Mandatory, the default of sqlcmd 18, on the same instance: TDS 7.4"
    sq -S localhost -C -Q "$tds"
    ;;
copy)
    f=${2:-module_08}
    echo "== /var/opt/mssql/backup/$f, from $src to $c"
    $engine cp "$src:/var/opt/mssql/backup/$f" - | $engine cp - "$c:/var/opt/mssql/backup/"
    $engine exec -u 0 "$c" chown -R mssql /var/opt/mssql/backup/"$f"
    $engine exec "$c" ls -l /var/opt/mssql/backup/"$f"
    ;;
restart)
    restart
    sq -S localhost -C -Q "SET NOCOUNT ON; SELECT sqlserver_start_time FROM sys.dm_os_sys_info;"
    ;;
remove)
    $engine rm -f "$c" >/dev/null
    echo "== $c removed"
    ;;
*)
    sed -n '3,15p' "$0"; exit 1
    ;;
esac
