#!/usr/bin/env bash
# Clips 3.2 and 3.3: the throwaway container for the two scripts that change the instance,
# model and tempdb. Runs from the root of the course repository, in a terminal, in about thirty seconds.
# It never touches the lab container sqladmcourse. With Podman: ENGINE=podman ./demos/module_03/02-throwaway-container.sh
# The password is the lab password of the README. The last line removes the container.
set -euo pipefail
engine=${ENGINE:-docker}
c=sqladm-03
pw=${MSSQL_SA_PASSWORD:-Course-2026!lab}
sq() { $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -I -W "$@"; }
wait_sql() { until sq -Q "SELECT 1" >/dev/null 2>&1; do sleep 2; done; }

echo "== a fresh SQL Server 2025, same image as the lab"
$engine run -d --name "$c" --memory 4g --cpus 2 -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
    -e MSSQL_AGENT_ENABLED=true -e "MSSQL_SA_PASSWORD=$pw" -e "SQLCMDPASSWORD=$pw" \
    mcr.microsoft.com/mssql/server:2025-CU7-ubuntu-24.04 >/dev/null
wait_sql

echo "== model as the template"
sq < demos/module_03/02b-model-template.sql

echo "== tempdb moved, effective at the next start"
sq < demos/module_03/03a-move-tempdb.sql
echo "-- files in the new folder before the restart:"
$engine exec "$c" ls -la /var/opt/mssql/tempdb

echo "== restart: SHUTDOWN stops SQL Server, and the container with it"
sq -Q "SHUTDOWN WITH NOWAIT;" || true
until [ "$($engine inspect -f '{{.State.Running}}' "$c")" = false ]; do sleep 1; done
$engine start "$c" >/dev/null
wait_sql
sq < demos/module_03/03b-check-tempdb.sql

echo "== the old files stay where they were, and are deleted by hand"
$engine exec "$c" bash -c 'ls /var/opt/mssql/tempdb; ls /var/opt/mssql/data/temp*; rm /var/opt/mssql/data/temp*; ls /var/opt/mssql/data'

echo "== remove the throwaway container"
$engine rm -f "$c" >/dev/null
