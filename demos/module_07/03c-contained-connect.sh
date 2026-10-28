#!/usr/bin/env bash
# Clip 7.3: the contained user CatalogSync connects to its database, and only there. Runs
# from the root of the course repository, in a terminal, in a few seconds, after
# 03b-contained-database.sql:
#   ENGINE=podman ./demos/module_07/03c-contained-connect.sh
# For the video: CONTAINER=sqladm-07 ENGINE=podman ./demos/module_07/03c-contained-connect.sh
# It writes nothing.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
as() { $engine exec -i -e SQLCMDPASSWORD='Web-Catalog-2026!lab' "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U CatalogSync -C -W -I -l 5 "$@"; }
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

echo "== 1. With the database named: the database checks the password"
as -d WebCatalog -Q "SET NOCOUNT ON; SELECT DB_NAME() AS current_database, USER_NAME() AS user_name, COUNT(*) AS courses FROM Catalog.Course;"

echo "== 2. From there, another database"
as -d WebCatalog -Q "USE PachadataTraining;"

echo "== 3. Without the database: the instance knows no such login"
as -Q "SELECT 1;"
admin -Q "SET NOCOUNT ON; EXEC sys.xp_readerrorlog 0, 1, N'CatalogSync';"
