#!/usr/bin/env bash
# Clip 9.4: events for the audit. Runs from the root of the course repository, in a
# terminal, in a few seconds, after 04a-server-audit.sql:
#   ENGINE=podman ./demos/module_09/04b-events.sh
# For the video: CONTAINER=sqladm-09 ENGINE=podman ./demos/module_09/04b-events.sh
# 1. The payroll accountant reads the current rate of three trainers, by a real connection.
# 2. A representative tries to read the rates, through EXECUTE AS USER: refused (229).
# 3. Two failed connections: an unknown login, then sa with a wrong password.
# 4. An administrator adds the accountant to a server role, then takes the role back.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
# A connection with a given login and password, passed by the environment, never by -P.
as() { $engine exec -i -e SQLCMDPASSWORD="$2" "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U "$1" -C -W -I -l 5 "${@:3}"; }
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

echo "== 1. The payroll accountant reads the rates"
as PachadataPayroll 'Payroll-2026!lab' -Q "SET NOCOUNT ON;
SELECT TOP (3) TrainerId, DailyRate FROM Trainer.TrainerRate
WHERE EndDate IS NULL ORDER BY TrainerId;"

echo "== 2. A representative tries the same"
admin -d PachadataTraining -Q "SET NOCOUNT ON;
EXECUTE AS USER = N'Margaux';
SELECT TOP (3) TrainerId, DailyRate FROM Trainer.TrainerRate;
REVERT;"

echo "== 3. Two failed connections"
as Intruder 'wrong-password' -Q "SELECT 1;"
as sa 'wrong-password' -Q "SELECT 1;"

echo "== 4. A server role given, then taken back"
admin -Q "ALTER SERVER ROLE dbcreator ADD MEMBER PachadataPayroll;"
admin -Q "ALTER SERVER ROLE dbcreator DROP MEMBER PachadataPayroll;"
