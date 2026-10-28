#!/usr/bin/env bash
# Clip 7.1: two failed connections, and what the error log says about them. Runs from the
# root of the course repository, in a terminal, in a few seconds, on the lab:
#   ENGINE=podman ./demos/module_07/01b-failed-logins.sh
# For the video: CONTAINER=sqladm-07 ENGINE=podman ./demos/module_07/01b-failed-logins.sh
# It creates nothing. The client receives the same message twice; the state of error 18456
# in the error log tells why each connection failed.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
# A connection with a given login and password, passed by the environment, never by -P.
as() { $engine exec -i -e SQLCMDPASSWORD="$2" "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U "$1" -C -W -I -l 5 "${@:3}"; }
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

echo "== 1. A login that does not exist yet"
as PachadataWeb 'Web-Site-2026!lab' -Q "SELECT 1;"

echo "== 2. sa, with a wrong password"
as sa 'not-the-password' -Q "SELECT 1;"

echo "== 3. The error log: one line for the state, one for the reason"
admin -Q "SET NOCOUNT ON; EXEC sys.xp_readerrorlog 0, 1, N'18456'; EXEC sys.xp_readerrorlog 0, 1, N'Login failed';"
