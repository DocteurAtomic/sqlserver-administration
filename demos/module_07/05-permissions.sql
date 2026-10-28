-- Clip 7.5: GRANT, DENY and REVOKE on the catalog, and the effective permissions of the
-- website. Played for the video on the throwaway container sqladm-07, after
-- 04b-database-roles.sql:
-- ci: skip (it needs the login of 02a-logins-users.sql)
-- On your lab, run it part by part. Parts 2 and 3 end on expected errors 230 and 229.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The catalog: every table and view of the schema Course, present and future, except the
--    two internal comment columns of Course.Course.
GRANT SELECT ON SCHEMA::Course TO WebApplication;
DENY SELECT ON Course.Course (PlanningComments, ProductionComments) TO WebApplication;
GO
-- 2. The effective permissions, under the identity of the user of the website.
EXECUTE AS USER = N'WebSite';
SELECT USER_NAME() AS user_name, ORIGINAL_LOGIN() AS original_login;
SELECT HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT') AS whole_table,
       HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT', N'Code', N'COLUMN') AS column_code,
       HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT', N'PlanningComments', N'COLUMN') AS column_comments,
       HAS_PERMS_BY_NAME(N'Course.Session', N'OBJECT', N'SELECT') AS sessions,
       HAS_PERMS_BY_NAME(N'Enrollment.Enrollment', N'OBJECT', N'SELECT') AS enrollments;
SELECT COUNT(*) AS readable_columns
FROM sys.fn_my_permissions(N'Course.Course', N'OBJECT')
WHERE permission_name = N'SELECT' AND subentity_name <> N'';
SELECT TOP (3) CourseId, Code, Duration FROM Course.Course ORDER BY CourseId;
GO
SELECT TOP (1) * FROM Course.Course;
GO
SELECT TOP (1) EnrollmentId FROM Enrollment.Enrollment;
GO
REVERT;
GO
-- 3. A fixed role that reads everything does not lift the DENY.
ALTER ROLE db_datareader ADD MEMBER WebSite;
EXECUTE AS USER = N'WebSite';
SELECT HAS_PERMS_BY_NAME(N'Enrollment.Enrollment', N'OBJECT', N'SELECT') AS enrollments,
       HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT', N'PlanningComments', N'COLUMN') AS column_comments;
REVERT;
ALTER ROLE db_datareader DROP MEMBER WebSite;
GO
-- 4. REVOKE removes what was set, GRANT or DENY: it does not refuse. Revoked, the DENY leaves
--    the column to the GRANT on the schema.
REVOKE SELECT ON Course.Course (PlanningComments, ProductionComments) FROM WebApplication;
EXECUTE AS USER = N'WebSite';
SELECT HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT', N'PlanningComments', N'COLUMN') AS column_comments;
REVERT;
DENY SELECT ON Course.Course (PlanningComments, ProductionComments) TO WebApplication;
GO
-- 5. The explicit permissions of the database, to read before and after any change.
SELECT pr.name AS principal_name, pe.state_desc, pe.permission_name,
       CASE pe.class
            WHEN 0 THEN N'DATABASE'
            WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + N'.' + OBJECT_NAME(pe.major_id)
                        + ISNULL(N' (' + COL_NAME(pe.major_id, pe.minor_id) + N')', N'')
            WHEN 3 THEN N'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE pe.class_desc
       END AS securable
FROM sys.database_permissions AS pe
JOIN sys.database_principals AS pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name NOT IN (N'public', N'guest', N'dbo')
ORDER BY pr.name, securable, pe.permission_name;
GO
