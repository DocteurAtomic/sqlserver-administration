#!/usr/bin/env bash
# Clip 10.4: the Agent's log, which says why the alerts do not fire on Linux. Runs from the
# host, in a terminal, in a second:
#   ENGINE=podman ./demos/module_10/10-agent-log.sh
# For the video: CONTAINER=sqladm-10 ENGINE=podman ./demos/module_10/10-agent-log.sh
# The log is /var/opt/mssql/log/sqlagent.out, written in UTF-16: iconv makes it readable.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
$engine exec "$c" sh -c 'iconv -f UTF-16LE -t UTF-8 /var/opt/mssql/log/sqlagent.out' \
    | tr -d '\r' | grep -E 'AlertEngine|alert cache|mail session|Database Mail profile|emailed to operator' | tail -n 8
