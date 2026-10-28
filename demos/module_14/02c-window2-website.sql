-- Clip 14.2, window 2: the website records the customer's purchase order on the same
-- invoice. Played for the video on sqladm-14, in its own SSMS window, after window 1:
-- ci: skip (it waits for window 1)
-- It waits until window 1 ends, then updates the row.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS session_id;
UPDATE Enrollment.Invoice
SET OrderReference = 'PO 4567830017'
WHERE InvoiceCode = 'FA2026-007499';
SELECT SYSDATETIME() AS updated_at, InvoiceCode, ReminderLevel, OrderReference
FROM Enrollment.Invoice
WHERE InvoiceCode = 'FA2026-007499';
