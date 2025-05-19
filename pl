https://www.interdb.jp/pg/pgsql11.html

https://edu.postgrespro.com/postgresql_internals-14_part1_en.pdf

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


-- check partiton and record count:

SELECT 
    inhrelid::regclass AS partition_name, 
    reltuples::bigint AS estimated_row_count
FROM pg_inherits
JOIN pg_class c ON inhrelid = c.oid
JOIN pg_stat_user_tables s ON inhrelid = s.relid
WHERE c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'application')
ORDER BY partition_name;

-- performance 

    SET LOCAL max_parallel_workers_per_gather = 4;
    SET LOCAL max_parallel_workers = 8;
    SET LOCAL parallel_setup_cost = 0.1;
    SET LOCAL parallel_tuple_cost = 0.1;

-- to pick the index scan 

SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT * FROM your_table WHERE some_column = 'some_value';

-- to enable the disk access 

SET random_page_cost = 1.1;
SET seq_page_cost = 0.5;

-- To check vacuum 

SELECT 
  relname AS table_name,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE relname IN ('table_a', 'table_b'); -- Specify your table names

-- pg_stat_statement 

SELECT 
  query,
  total_exec_time,
  calls,
  mean_exec_time,
  max_exec_time,
  min_exec_time,
  rows,
  shared_blks_hit,
  shared_blks_read,
  shared_blks_written,
  temp_blks_read,
  temp_blks_written,
  blk_read_time,
  blk_write_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;


-- Find slow queries with high disk usage:

SELECT 
  query, 
  total_exec_time, 
  calls, 
  mean_exec_time, 
  blk_read_time, 
  blk_write_time
FROM pg_stat_statements
WHERE blk_read_time > 1000 -- Adjust based on threshold
ORDER BY total_exec_time DESC;

--Top queries by execution time:

SELECT query, total_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

--Most frequently executed queries:

SELECT query, calls
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;

-- parallelism

SET max_parallel_workers_per_gather = 4; -- Example: Allow up to 4 workers for a query
SET parallel_tuple_cost = 0.1; -- Lowering this may trigger more parallelism
SET parallel_setup_cost = 1000; -- Adjust as necessary
SET max_parallel_workers = 8; -- Allow up to 8 parallel workers for the entire system



-- join

-- Assuming temp_result has: id, max_h_id, min_h_id, c_id, some_column

INSERT INTO temp_result (id, max_h_id, min_h_id, c_id, some_column)
SELECT
  a.id,
  b.h_id AS max_h_id,
  min_tbl.min_h_id,
  b.c_id,
  c.some_column
FROM tb1 a
JOIN tb2 b ON a.id = b.id
JOIN (
    SELECT id, MAX(h_id) AS max_h_id
    FROM tb2
    GROUP BY id
) AS max_tbl ON b.id = max_tbl.id AND b.h_id = max_tbl.max_h_id
JOIN (
    SELECT id, MIN(h_id) AS min_h_id
    FROM tb2
    GROUP BY id
) AS min_tbl ON b.id = min_tbl.id
JOIN tb3 c ON b.c_id = c.c_id;

    
