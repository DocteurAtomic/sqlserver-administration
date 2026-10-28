-- Clip 14.2, window 3: a reader and a second writer, after windows 1 and 2.
-- ci: skip (the update waits for windows 1 and 2)
-- 1. The customer's account page reads the invoice: with RCSI, it does not wait, and sees
--    the last committed version of the row, without the reminder of window 1.
-- 2. The reminder batch updates the same invoice: it waits, like window 2.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS session_id;
SELECT SYSDATETIME() AS read_at, InvoiceCode, ReminderLevel, ReminderDate, OrderReference
FROM Enrollment.Invoice
WHERE InvoiceCode = 'FA2026-007499';
UPDATE Enrollment.Invoice
SET DueDate = DueDate
WHERE InvoiceCode = 'FA2026-007499';
SELECT SYSDATETIME() AS updated_at;
