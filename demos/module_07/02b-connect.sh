#!/usr/bin/env bash
# Clips 7.2 and 7.3: a real connection under the login of the website, PachadataWeb, without
# naming a database. Runs from the root of the course repository, in a terminal, in a second:
#   ENGINE=podman ./demos/module_07/02b-connect.sh
# For the video: CONTAINER=sqladm-07 ENGINE=podman ./demos/module_07/02b-connect.sh
# It writes nothing. Before the user exists, the connection fails on its default database;
# after, it enters and reads where it is, who it is, and what it can see.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
# The password goes through the environment, never on the command line.
$engine exec -i -e SQLCMDPASSWORD='Web-Site-2026!lab' "$c" \
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U PachadataWeb -C -W -I -l 5 <<'SQL'
SET NOCOUNT ON;
SELECT DB_NAME() AS current_database, SUSER_SNAME() AS login_name, USER_NAME() AS user_name;
SELECT TOP (3) CourseId, Code FROM Course.Course ORDER BY CourseId;
SELECT name FROM sys.sql_logins ORDER BY name;
GO
SQL
