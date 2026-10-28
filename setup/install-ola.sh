#!/usr/bin/env bash
# Run by setup/install.sh; run it again by hand when DBA is missing, from the root of the
# repository:
#   ./setup/install-ola.sh          (with Podman: ENGINE=podman ./setup/install-ola.sh)
# 1. Gives the backup folder of the container, /var/opt/mssql/backup, to the mssql user:
#    setup/install.sh creates it as root, and SQL Server cannot write there otherwise
#    (xp_create_subdir returns "error 5, Access is denied").
# 2. Downloads Ola Hallengren's Maintenance Solution (MIT license,
#    https://ola.hallengren.com) and installs it in a database DBA, with its Agent jobs.
#    The script starts with a UTF-8 BOM that sqlcmd refuses: it is removed. Its jobs back up
#    to /var/opt/mssql/backup instead of the default folder of the instance, which in the
#    container is the data folder.
# Running it again reinstalls the procedures; the jobs are kept.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
sqlcmd() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -I "$@"; }

$engine exec -u 0 $c mkdir -p /var/opt/mssql/backup
$engine exec -u 0 $c chown mssql:mssql /var/opt/mssql/backup

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/MaintenanceSolution.sql" https://ola.hallengren.com/scripts/MaintenanceSolution.sql
sed -i -e '1s/^\xEF\xBB\xBF//' \
       -e 's/^USE \[master\]/USE [DBA]/' \
       -e "s|^\(DECLARE @BackupDirectory nvarchar(max) *\)= NULL|\1= N'/var/opt/mssql/backup'|" \
       "$tmp/MaintenanceSolution.sql"
grep -m1 '^Version:' "$tmp/MaintenanceSolution.sql"

sqlcmd -Q "IF DB_ID(N'DBA') IS NULL CREATE DATABASE DBA; ALTER DATABASE DBA SET RECOVERY SIMPLE;"
sqlcmd < "$tmp/MaintenanceSolution.sql" >/dev/null
sqlcmd -W -Q "SET NOCOUNT ON; SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'DatabaseBackup%' ORDER BY name;"
