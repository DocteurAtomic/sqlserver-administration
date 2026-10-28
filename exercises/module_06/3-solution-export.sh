#!/usr/bin/env bash
# Module 6 exercise: solution of part 3, the exports. Runs from the root of the course
# repository, after 2-solution.sql:  ./exercises/module_06/3-solution-export.sh
# (with Podman: ENGINE=podman). bcp runs inside the container, as the user mssql, in
# /var/opt/mssql/exchange/exercise_06, the folder 1-start.sql created.
# 1. The separators the data contains, before choosing one.
# 2. The payments since 2020 in native format (queryout), loaded back by bcp in with the
#    TABLOCK hint, without then with -E (keep the identity values).
# 3. The payments as text with a semicolon, and the format file.
set -euo pipefail
engine=${ENGINE:-docker}
c=${CONTAINER:-sqladmcourse}
db=PachadataTraining_Ex06
bcp() {
    $engine exec $c bash -c 'cd /var/opt/mssql/exchange/exercise_06 &&
        /opt/mssql-tools18/bin/bcp "$@" -S localhost -U sa -P "$SQLCMDPASSWORD" -u' bcp "$@" \
        | grep -v -e 'rows successfully bulk-copied' -e 'rows sent to SQL Server' -e '^$' || true
}
sql() { $engine exec -i ${SQLCMDPASSWORD:+-e SQLCMDPASSWORD} $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -W -I -b -Q "SET NOCOUNT ON; $1"; }

echo "== 1. Commas, semicolons and tabs in the text columns of the payments"
sql "SELECT SUM(CASE WHEN CONCAT(InvoiceCode, CheckNumber, SlipNumber) LIKE '%,%' THEN 1 ELSE 0 END) AS commas,
            SUM(CASE WHEN CONCAT(InvoiceCode, CheckNumber, SlipNumber) LIKE '%;%' THEN 1 ELSE 0 END) AS semicolons,
            SUM(CASE WHEN CONCAT(InvoiceCode, CheckNumber, SlipNumber) LIKE '%' + CHAR(9) + '%' THEN 1 ELSE 0 END) AS tabs
     FROM $db.Enrollment.Payment;"

echo "== 2. Native export of the payments since 2020, then two loads into empty copies of the table"
bcp "SELECT PaymentId, InvoiceCode, PaymentDate, CheckNumber, SlipNumber, Amount, PaymentMethodCode
     FROM $db.Enrollment.Payment WHERE PaymentDate >= '20200101'" queryout payment.bcp -n
sql "USE $db; DROP TABLE IF EXISTS dbo.PaymentNative, dbo.PaymentNativeKeep;
     SELECT TOP (0) * INTO dbo.PaymentNative FROM Enrollment.Payment;
     SELECT TOP (0) * INTO dbo.PaymentNativeKeep FROM Enrollment.Payment;"
bcp $db.dbo.PaymentNative in payment.bcp -n -h TABLOCK
bcp $db.dbo.PaymentNativeKeep in payment.bcp -n -h TABLOCK -E

echo "== 3. Text export with a semicolon, and its format file"
bcp $db.Enrollment.Payment out payment.csv -c '-t;'
bcp $db.Enrollment.Payment format /dev/null -c '-t;' -f payment.fmt
$engine exec $c bash -c 'cd /var/opt/mssql/exchange/exercise_06 && head -3 payment.csv && cat payment.fmt && ls -l'
