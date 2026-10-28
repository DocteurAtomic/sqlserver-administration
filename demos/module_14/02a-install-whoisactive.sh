#!/usr/bin/env bash
# Clip 14.2: install sp_WhoIsActive in the database DBA of the lab. Runs from the root of the
# course repository, in a terminal, in a few seconds:
#   ENGINE=podman ./demos/module_14/02a-install-whoisactive.sh
# For the video: CONTAINER=sqladm-14 ENGINE=podman ./demos/module_14/02a-install-whoisactive.sh
# sp_WhoIsActive is written by Adam Machanic, under the GPLv3 license:
#   https://github.com/amachanic/sp_whoisactive
# The script takes the release of 9 April 2026 (tag 20260409, "v2200.20260409" in its
# header), the file at the root of the repository, which targets SQL Server 2022 and later;
# the folders 2019 and 2008 of the repository hold the versions for older releases.
# It checks the SHA-256 of the file before running it, and installs the procedure in DBA,
# the administration database of Ola Hallengren's scripts. 99-cleanup.sql drops it, so that
# the lab goes back to its base state; on a production instance, it stays.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
tag=20260409
sum=4c528a139d7e2259e46a7656d056fb359fc8472818cbc9569ae83ff96278c466
sqlcmd() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} "$c" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -I -W "$@"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/sp_WhoIsActive.sql" \
    "https://raw.githubusercontent.com/amachanic/sp_whoisactive/$tag/sp_WhoIsActive.sql"
if command -v sha256sum >/dev/null; then got=$(sha256sum "$tmp/sp_WhoIsActive.sql" | cut -d' ' -f1)
else got=$(shasum -a 256 "$tmp/sp_WhoIsActive.sql" | cut -d' ' -f1); fi
if [ "$got" != "$sum" ]; then
    echo "Checksum mismatch for sp_WhoIsActive.sql (tag $tag): not installed." >&2
    exit 1
fi
grep -m1 'Who Is Active? v' "$tmp/sp_WhoIsActive.sql"

sqlcmd -Q "IF DB_ID(N'DBA') IS NULL RAISERROR (N'DBA is missing: run ./setup/install-ola.sh first.', 16, 1);"
sqlcmd -d DBA < "$tmp/sp_WhoIsActive.sql" >/dev/null
sqlcmd -d DBA -Q "SET NOCOUNT ON;
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + name AS installed, create_date
FROM sys.procedures WHERE name = N'sp_WhoIsActive';"
