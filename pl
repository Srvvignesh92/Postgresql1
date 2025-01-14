-- Check all roles and their attributes
SELECT rolname AS role_name,
       rolsuper AS is_superuser,
       rolinherit AS can_inherit,
       rolcreaterole AS can_create_role,
       rolcreatedb AS can_create_db,
       rolcanlogin AS can_login,
       rolreplication AS can_replication,
       rolbypassrls AS bypasses_rls
FROM pg_roles;

-- Check role memberships
SELECT roleid::regrole AS member,
       member::regrole AS belongs_to,
       grantor::regrole AS granted_by,
       admin_option
FROM pg_auth_members;

-- Check privileges on schemas
SELECT grantee,
       privilege_type,
       table_schema
FROM information_schema.role_schema_grants
WHERE grantee = 'your_user_or_role'; -- Replace with the role name you are querying

-- Check privileges on tables
SELECT grantee,
       privilege_type,
       table_schema,
       table_name
FROM information_schema.role_table_grants
WHERE grantee = 'your_user_or_role'; -- Replace with the role name you are querying

-- Check privileges on sequences
SELECT grantee,
       privilege_type,
       sequence_schema,
       sequence_name
FROM information_schema.role_sequence_grants
WHERE grantee = 'your_user_or_role'; -- Replace with the role name you are querying

-- Check privileges on functions
SELECT grantee,
       privilege_type,
       specific_schema,
       routine_name
FROM information_schema.role_routine_grants
WHERE grantee = 'your_user_or_role'; -- Replace with the role name you are querying

-- Check privileges on databases
SELECT datname AS database_name,
       pg_catalog.pg_get_userbyid(datdba) AS owner,
       has_database_privilege(datname, 'CONNECT') AS can_connect,
       has_database_privilege(datname, 'TEMP') AS can_temp
FROM pg_database;

-- Check all default privileges for a user or role
SELECT defaclrole::regrole AS role_name,
       defaclnamespace::regnamespace AS schema_name,
       defaclobjtype AS object_type,
       defaclacl AS default_privileges
FROM pg_default_acl;
