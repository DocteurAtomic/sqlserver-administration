-- Clip 7.4: the database roles, what db_owner really gives, and the role of the website.
-- Played for the video on the throwaway container sqladm-07, after 02a-logins-users.sql:
-- ci: skip (it needs the login of 02a-logins-users.sql)
-- On your lab, run it in one go. The two users of part 2 have no login, and the script drops
-- them; the role WebApplication stays for the next clips.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The fixed database roles.
SELECT name FROM sys.database_principals
WHERE type = 'R' AND is_fixed_role = 1
ORDER BY name;
GO
-- 2. Two developers, one in db_datareader, the other in db_owner. Users without login are
--    enough to try their rights by EXECUTE AS USER.
CREATE USER DevReader WITHOUT LOGIN;
CREATE USER DevOwner WITHOUT LOGIN;
ALTER ROLE db_datareader ADD MEMBER DevReader;
ALTER ROLE db_owner ADD MEMBER DevOwner;
GO
EXECUTE AS USER = N'DevReader';
SELECT USER_NAME() AS user_name,
       (SELECT COUNT(*) FROM sys.fn_my_permissions(NULL, N'DATABASE')) AS database_permissions,
       HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'ALTER ANY USER') AS alter_any_user,
       HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'BACKUP DATABASE') AS backup_database,
       HAS_PERMS_BY_NAME(N'Enrollment.Invoice', N'OBJECT', N'DELETE') AS delete_invoices;
REVERT;
EXECUTE AS USER = N'DevOwner';
SELECT USER_NAME() AS user_name,
       (SELECT COUNT(*) FROM sys.fn_my_permissions(NULL, N'DATABASE')) AS database_permissions,
       HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'ALTER ANY USER') AS alter_any_user,
       HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'BACKUP DATABASE') AS backup_database,
       HAS_PERMS_BY_NAME(N'Enrollment.Invoice', N'OBJECT', N'DELETE') AS delete_invoices;
-- A member of db_owner adds whoever it wants to db_owner.
CREATE USER DevFriend WITHOUT LOGIN;
ALTER ROLE db_owner ADD MEMBER DevFriend;
SELECT USER_NAME(rm.member_principal_id) AS db_owner_member
FROM sys.database_role_members AS rm
WHERE rm.role_principal_id = USER_ID(N'db_owner');
REVERT;
GO
ALTER ROLE db_owner DROP MEMBER DevFriend;
ALTER ROLE db_owner DROP MEMBER DevOwner;
ALTER ROLE db_datareader DROP MEMBER DevReader;
DROP USER DevFriend;
DROP USER DevOwner;
DROP USER DevReader;
GO
-- 3. The role of the website, owned by dbo, with the user WebSite as its only member. The
--    rights go to the role, never to the user.
CREATE ROLE WebApplication AUTHORIZATION dbo;
ALTER ROLE WebApplication ADD MEMBER WebSite;
SELECT USER_NAME(rm.role_principal_id) AS role_name, USER_NAME(rm.member_principal_id) AS member_name
FROM sys.database_role_members AS rm
WHERE rm.role_principal_id = USER_ID(N'WebApplication');
GO
