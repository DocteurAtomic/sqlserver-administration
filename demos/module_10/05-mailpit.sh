#!/usr/bin/env bash
# Clip 10.2: the messages Mailpit received, read through its API. Runs from the host, in a
# terminal, after 04-database-mail.sql:
#   ./demos/module_10/05-mailpit.sh
# The same messages are in the web interface of Mailpit: http://localhost:8025. MAILPORT
# changes the port, as in compose.yaml. Only curl, grep and sed: no JSON tool needed.
# One line per message, newest first: time (UTC), sender, first recipient, subject, number
# of attachments.
set -euo pipefail
url=http://localhost:${MAILPORT:-8025}/api/v1
curl -fsS "$url/messages?limit=20" \
    | sed 's/},{"ID"/}\n{"ID"/g' \
    | sed -n 's/.*"From":{[^}]*"Address":"\([^"]*\)"}.*"To":\[{[^}]*"Address":"\([^"]*\)"}.*"Subject":"\([^"]*\)","Created":"\([^"]*\)".*"Attachments":\([0-9]*\).*/\4  \1 -> \2  "\3"  attachments: \5/p'
