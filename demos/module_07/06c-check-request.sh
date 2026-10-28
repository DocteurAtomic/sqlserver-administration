#!/usr/bin/env bash
# Clip 7.6: the request of the developer, checked by a real connection of the website and by
# the inventory of what its login holds. Runs from the root of the course repository, in a
# terminal, in a few seconds, after 06b-module-signing.sql:
#   ENGINE=podman ./demos/module_07/06c-check-request.sh
# For the video: CONTAINER=sqladm-07 ENGINE=podman ./demos/module_07/06c-check-request.sh
# It writes nothing.
set -uo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
web() { $engine exec -i -e SQLCMDPASSWORD='Web-Site-2026!lab' "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U PachadataWeb -C -W -I -l 5 "$@"; }
admin() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I "$@"; }

echo "== 1. The website, connected as PachadataWeb"
web <<'SQL'
SET NOCOUNT ON;
CREATE TABLE #catalog (Catalog nvarchar(max));
INSERT #catalog EXEC Course.CatalogJson @LanguageCode = 'EN';
SELECT LEN(Catalog) AS catalog_length, LEFT(Catalog, 60) AS catalog_start FROM #catalog;
EXEC Web.SearchSessions @LanguageCode = 'EN';
GO
SELECT TOP (1) InvoiceCode FROM Enrollment.Invoice;
GO
SQL

echo "== 2. What the login holds, read by the administrator"
admin <<'SQL'
SET NOCOUNT ON;
SELECT IS_SRVROLEMEMBER(N'sysadmin', N'PachadataWeb') AS is_sysadmin,
       (SELECT COUNT(*) FROM sys.server_role_members AS rm
        WHERE rm.member_principal_id = SUSER_ID(N'PachadataWeb')) AS server_roles,
       (SELECT COUNT(*) FROM sys.server_permissions AS sp
        WHERE sp.grantee_principal_id = SUSER_ID(N'PachadataWeb')
          AND sp.permission_name <> N'CONNECT SQL') AS server_permissions;
USE PachadataTraining;
SELECT USER_NAME(rm.role_principal_id) AS role_name
FROM sys.database_role_members AS rm
WHERE rm.member_principal_id = USER_ID(N'WebSite');
SELECT pe.state_desc, pe.permission_name,
       CASE pe.class WHEN 3 THEN N'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE OBJECT_SCHEMA_NAME(pe.major_id) + N'.' + OBJECT_NAME(pe.major_id)
                 + ISNULL(N' (' + COL_NAME(pe.major_id, pe.minor_id) + N')', N'') END AS securable
FROM sys.database_permissions AS pe
WHERE pe.grantee_principal_id = USER_ID(N'WebApplication')
ORDER BY securable;
GO
SQL
