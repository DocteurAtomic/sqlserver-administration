#!/usr/bin/env bash
# Clip 2.6: the dedicated administrator connection (DAC). Played for the video on the
# throwaway container sqladm-02, after 05-configure-instance.sql:
#   CONTAINER=sqladm-02 ENGINE=podman ./demos/module_02/06-dac.sh
# It runs as is on your lab (CONTAINER=sqladmcourse by default); step 4 then fails, until
# remote admin connections is set to 1. It takes about half a minute and changes no data:
# the killed transaction is rolled back, the waiting update writes the same value.
# 1. A session opens a transaction on a course and keeps it; a second one waits for it.
# 2. The DAC, opened by sqlcmd -S admin:localhost, finds the head of the chain and kills it.
# 3. A second DAC while the first is open: refused, and the error log says why.
# 4. The DAC through the address of the server instead of the loopback.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
here=$(dirname "$0")
sqlcmd() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -U sa -C -W -I -l 5 "$@"; }

echo "== 1. Two sessions block each other on course 1"
sqlcmd -S localhost -d PachadataTraining -Q "BEGIN TRANSACTION; UPDATE Course.Course SET MaxAttendees = MaxAttendees + 1 WHERE CourseId = 1; WAITFOR DELAY '00:02:00'; COMMIT;" >/dev/null 2>&1 &
sleep 2
sqlcmd -S localhost -d PachadataTraining -Q "UPDATE Course.Course SET MaxAttendees = MaxAttendees WHERE CourseId = 1;" >/dev/null 2>&1 &
sleep 2

echo "== 2. The DAC"
sqlcmd -S admin:localhost < "$here/06-dac-session.sql" &
dac=$!
sleep 4

echo "== 3. A second DAC while the first is open"
sqlcmd -S admin:localhost -Q "SELECT 1;"
wait $dac
sqlcmd -S localhost -Q "EXEC sys.xp_readerrorlog 0, 1, N'17810'; EXEC sys.xp_readerrorlog 0, 1, N'dedicated administrator connections already exists';"
wait

echo "== 4. The DAC through the address of the server, port 1434"
sqlcmd -S "$($engine exec $c hostname),1434" -Q "SET NOCOUNT ON; SELECT e.name AS endpoint_name FROM sys.dm_exec_sessions AS s JOIN sys.endpoints AS e ON e.endpoint_id = s.endpoint_id WHERE s.session_id = @@SPID;"
sqlcmd -S localhost -d PachadataTraining -Q "SET NOCOUNT ON; SELECT CourseId, MaxAttendees FROM Course.Course WHERE CourseId = 1;"
