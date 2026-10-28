-- Module 5 exercise: start. Runs on your lab, in one session. It takes about five seconds.
-- 1. Restores a copy of the database, PachadataTraining_Ex05. The exercise never writes in
--    PachadataTraining.
-- 2. Plays the nightly load of the accounting team on the copy: two constraints disabled for
--    the load, then enabled again without WITH CHECK.
-- The solution drops the copy.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining_Ex05';
GO
USE PachadataTraining_Ex05;
GO
ALTER TABLE Enrollment.Invoice NOCHECK CONSTRAINT chk_Invoice_InvoiceDate;
ALTER TABLE Enrollment.InvoiceLine NOCHECK CONSTRAINT fk_InvoiceLine_Invoice;
-- ... the load ...
ALTER TABLE Enrollment.Invoice CHECK CONSTRAINT chk_Invoice_InvoiceDate;
ALTER TABLE Enrollment.InvoiceLine CHECK CONSTRAINT fk_InvoiceLine_Invoice;
GO
-- The table of part 1 and part 3: one million US prospects in nvarchar, stored as a heap.
SELECT index_id, row_count, used_page_count
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Contact.ProspectUS_N');
-- The invoices of part 4, per year of creation.
SELECT YEAR(CreationDate) AS creation_year, COUNT(*) AS invoices
FROM Enrollment.Invoice
GROUP BY YEAR(CreationDate)
ORDER BY creation_year;
GO
