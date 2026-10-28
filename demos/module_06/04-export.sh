#!/usr/bin/env bash
# Clip 6.2: exporting the invoices with bcp. Runs from the root of the course repository, on
# the lab, after 00-setup.sql:  ./demos/module_06/04-export.sh  (with Podman: ENGINE=podman)
# bcp runs inside the container, as the user mssql, and writes in /var/opt/mssql/exchange,
# the folder 00-setup.sql created. It takes a few seconds.
# 1. A first export with a comma between the fields, and why it cannot be read back.
# 2. The export with a semicolon, absent from the data, and its format file.
# 3. The native export, for a transfer from SQL Server to SQL Server.
# 4. The request of the accounting team: the invoices of a month, by queryout.
# The password of sa comes from SQLCMDPASSWORD, set in the container; -u trusts the
# self-signed certificate of the lab. On a server: -T (Windows), a dedicated login, a real
# certificate.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
bcp() {  # bcp in the container, from the exchange folder, without the progress lines
    $engine exec $c bash -c 'cd /var/opt/mssql/exchange &&
        /opt/mssql-tools18/bin/bcp "$@" -S localhost -U sa -P "$SQLCMDPASSWORD" -u' bcp "$@" \
        | grep -v -e 'rows successfully bulk-copied' -e '^$' || true
}
sql() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I -h -1 -Q "SET NOCOUNT ON; $1"; }
in_container() { $engine exec $c bash -c "cd /var/opt/mssql/exchange && $1"; }

echo "== 1. A comma between the fields"
bcp PachadataTraining.Enrollment.Invoice out invoice_comma.csv -c -t,
in_container "grep -m 1 'Wrong recipient' invoice_comma.csv"
echo "== Invoices whose text columns contain a comma, then a semicolon"
sql "SELECT SUM(CASE WHEN CONCAT(OrderReference, Reason) LIKE '%,%' THEN 1 ELSE 0 END),
            SUM(CASE WHEN CONCAT(OrderReference, Reason) LIKE '%;%' THEN 1 ELSE 0 END)
     FROM PachadataTraining.Enrollment.Invoice;"

echo "== 2. A semicolon between the fields, then the format file"
bcp PachadataTraining.Enrollment.Invoice out invoice.csv -c '-t;'
bcp PachadataTraining.Enrollment.Invoice format /dev/null -c '-t;' -f invoice.fmt
in_container "head -2 invoice.csv; head -5 invoice.fmt; tail -1 invoice.fmt"

echo "== 3. The native format"
bcp PachadataTraining.Enrollment.Invoice out invoice.bcp -n

echo "== 4. The invoices of October 2026 for the accounting software"
bcp "SELECT InvoiceCode, InvoiceDate, NetAmount, GrossAmount, VatRate
     FROM PachadataTraining.Enrollment.Invoice
     WHERE InvoiceDate >= '20261001' AND InvoiceDate < '20261101'
     ORDER BY InvoiceCode" queryout invoice_2026_10.csv -c '-t;'
in_container "head -3 invoice_2026_10.csv; wc -l invoice_2026_10.csv; ls -l"
