#!/usr/bin/env bash
# Clip 3.1: sqlcmd. Runs from the root of the course repository, on the lab, in a terminal.
# Reads the instance and changes nothing. With Podman: ENGINE=podman ./demos/module_03/01-sqlcmd.sh
# The container brings sqlcmd (ODBC) in /opt/mssql-tools18, and SQLCMDPASSWORD in its
# environment. sqlcmd (Go), installed on your own machine, is used when it is on your PATH.
engine=${ENGINE:-docker}
sq() { $engine exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C "$@"; }

echo "== 1. Which sqlcmd: the ODBC variant answers -? with its banner"
sq -? | head -3

echo "== 2. A scripting variable given by -v"
sq -b -W -d PachadataTraining -v SchemaName=Enrollment \
   -Q "SET NOCOUNT ON; SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID(N'\$(SchemaName)') ORDER BY name;"

echo "== 3. :setvar in the script wins over -v"
printf ':setvar SchemaName "Contact"\nSELECT N'"'"'$(SchemaName)'"'"' AS schema_name;\nGO\n' \
  | sq -W -v SchemaName=Enrollment

echo "== 4. The exit code, without and with -b"
sq -Q "SELECT 1/0;"; echo "exit code without -b: $?"
sq -b -Q "SELECT 1/0;"; echo "exit code with -b: $?"

echo "== 5. sqlcmd (Go) on this machine, if installed"
if command -v sqlcmd >/dev/null; then
    sqlcmd --version | head -3
    SQLCMDPASSWORD=${MSSQL_SA_PASSWORD:-Course-2026!lab} \
        sqlcmd -S localhost,${SQLPORT:-14433} -U sa -C -b -W -Q "SET NOCOUNT ON; SELECT @@SERVERNAME AS server_name;"
else
    echo "sqlcmd (Go) is not installed here: winget install sqlcmd, brew install sqlcmd, or apt/dnf install sqlcmd"
fi
