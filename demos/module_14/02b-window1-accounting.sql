-- Clip 14.2, window 1: the accountant sends the first reminder of an invoice, in a
-- transaction that the screen leaves open. Played for the video on sqladm-14, in its own
-- SSMS window, which stays open:
-- ci: skip (it leaves a transaction open: the other windows need it)
-- 02e-kill.sql ends it. Nothing is ever committed.
USE PachadataTraining;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 1, ReminderDate = '2026-10-28'
WHERE InvoiceCode = 'FA2026-007499';
SELECT @@SPID AS session_id, @@TRANCOUNT AS open_transactions;
-- No COMMIT: the window stays open, the session sleeps, and its lock stays.
