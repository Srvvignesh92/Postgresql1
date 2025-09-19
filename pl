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



-- Assuming temp_result has: id, max_h_id, min_h_id, o_data, c_data

INSERT INTO temp_result (id, max_h_id, min_h_id, o_data, c_data)
SELECT
  a.id,
  max_tbl.max_h_id,
  min_tbl.min_h_id,
  o_row.o_data,
  c_row.c_data
FROM a
JOIN (
    SELECT id, MAX(h_id) AS max_h_id
    FROM b
    GROUP BY id
) AS max_tbl ON a.id = max_tbl.id
JOIN (
    SELECT id, MIN(h_id) AS min_h_id
    FROM b
    GROUP BY id
) AS min_tbl ON a.id = min_tbl.id
-- Get o_data for min_h_id
JOIN b o_row ON a.id = o_row.id AND o_row.h_id = min_tbl.min_h_id
-- Get c_data for max_h_id
JOIN b c_row ON a.id = c_row.id AND c_row.h_id = max_tbl.max_h_id;

-- index _ fk disable - enable 

CREATE SCHEMA IF NOT EXISTS migration_helper;

CREATE TABLE migration_helper.maintenance_metadata (
    object_type TEXT,           -- 'INDEX' or 'FK'
    table_schema TEXT,
    table_name TEXT,
    object_name TEXT,
    ddl TEXT,
    created_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE PROCEDURE migration_helper.drop_constraints_and_indexes(p_schema TEXT, p_tables TEXT[])
LANGUAGE plpgsql
AS $$
DECLARE
    t TEXT;
    idx RECORD;
    fk RECORD;
    idx_count INT;
    fk_count INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();

    FOREACH t IN ARRAY p_tables
    LOOP
        idx_count := 0;
        fk_count := 0;

        FOR idx IN
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE schemaname = p_schema
              AND tablename = t
              AND indexname NOT IN (
                  SELECT conname FROM pg_constraint
                  WHERE contype IN ('p', 'u') AND conrelid = format('%I.%I', p_schema, t)::regclass
              )
        LOOP
            INSERT INTO migration_helper.maintenance_metadata(object_type, table_schema, table_name, object_name, ddl)
            VALUES ('INDEX', p_schema, t, idx.indexname, idx.indexdef);

            EXECUTE format('DROP INDEX IF EXISTS %I.%I', p_schema, idx.indexname);
            idx_count := idx_count + 1;
        END LOOP;

        FOR fk IN
            SELECT conname, pg_get_constraintdef(c.oid) AS ddl
            FROM pg_constraint c
            JOIN pg_class rel ON rel.oid = c.conrelid
            JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
            WHERE c.contype = 'f'
              AND nsp.nspname = p_schema
              AND rel.relname = t
        LOOP
            INSERT INTO migration_helper.maintenance_metadata(object_type, table_schema, table_name, object_name, ddl)
            VALUES ('FK', p_schema, t, fk.conname, fk.ddl);

            EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', p_schema, t, fk.conname);
            fk_count := fk_count + 1;
        END LOOP;

        RAISE NOTICE 'Table: % - Dropped Indexes: %, Dropped FKs: %', t, idx_count, fk_count;
    END LOOP;

    end_time := clock_timestamp();
    RAISE NOTICE '⏱ Drop Phase Completed in: % seconds', round(EXTRACT(EPOCH FROM end_time - start_time), 2);
END;
$$;


CREATE OR REPLACE PROCEDURE migration_helper.recreate_constraints_and_indexes(p_schema TEXT, p_tables TEXT[])
LANGUAGE plpgsql
AS $$
DECLARE
    t TEXT;
    rec RECORD;
    idx_count INT;
    fk_count INT;
    total_expected INT;
    total_restored INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();
    total_restored := 0;

    FOREACH t IN ARRAY p_tables
    LOOP
        idx_count := 0;
        fk_count := 0;

        FOR rec IN
            SELECT * FROM migration_helper.maintenance_metadata
            WHERE table_schema = p_schema AND table_name = t
            ORDER BY created_at
        LOOP
            IF rec.object_type = 'INDEX' THEN
                EXECUTE rec.ddl;
                idx_count := idx_count + 1;
            ELSIF rec.object_type = 'FK' THEN
                EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s',
                               rec.table_schema, rec.table_name, rec.object_name, rec.ddl);
                fk_count := fk_count + 1;
            END IF;

            total_restored := total_restored + 1;
        END LOOP;

        RAISE NOTICE 'Table: % - Recreated Indexes: %, Recreated FKs: %', t, idx_count, fk_count;
    END LOOP;

    total_expected := (
        SELECT COUNT(*) FROM migration_helper.maintenance_metadata
        WHERE table_schema = p_schema AND table_name = ANY(p_tables)
    );

    IF total_restored = total_expected THEN
        RAISE NOTICE '✅ All constraints and indexes successfully restored.';
    ELSE
        RAISE WARNING '⚠️ Restored %, but expected % from metadata.', total_restored, total_expected;
    END IF;

    DELETE FROM migration_helper.maintenance_metadata
    WHERE table_schema = p_schema AND table_name = ANY(p_tables);

    end_time := clock_timestamp();
    RAISE NOTICE '⏱ Restore Phase Completed in: % seconds', round(EXTRACT(EPOCH FROM end_time - start_time), 2);
END;
$$;


CALL migration_helper.drop_constraints_and_indexes('application', ARRAY['orders', 'customers']);
CALL migration_helper.recreate_constraints_and_indexes('application', ARRAY['orders', 'customers']);





    ---


    -- Check if any constraints are invalid (should return 0 rows if all are valid)
SELECT 
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    con.convalidated AS is_validated
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE con.convalidated = false  -- Invalid constraints
  AND n.nspname NOT IN ('information_schema', 'pg_catalog')
ORDER BY n.nspname, c.relname, con.conname;

--

-- Detailed FK constraint status check
SELECT 
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    CASE con.contype
        WHEN 'f' THEN 'FOREIGN KEY'
        WHEN 'p' THEN 'PRIMARY KEY'  
        WHEN 'u' THEN 'UNIQUE'
        WHEN 'c' THEN 'CHECK'
        WHEN 'x' THEN 'EXCLUDE'
        ELSE con.contype::text
    END AS constraint_description,
    con.convalidated AS is_validated,
    CASE 
        WHEN con.convalidated THEN '✅ VALID'
        ELSE '❌ INVALID - NEEDS VALIDATION'
    END AS status,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE con.contype = 'f'  -- Only foreign keys
  AND n.nspname NOT IN ('information_schema', 'pg_catalog')
ORDER BY 
    n.nspname, 
    c.relname, 
    con.convalidated,  -- Invalid ones first
    con.conname;

    --



    -- Check constraints on partitioned tables and their partitions
WITH partition_info AS (
    SELECT 
        schemaname,
        tablename,
        CASE 
            WHEN schemaname||'.'||tablename IN (
                SELECT schemaname||'.'||partitiontablename 
                FROM pg_partitions
            ) THEN 'PARTITION'
            WHEN schemaname||'.'||tablename IN (
                SELECT schemaname||'.'||tablename 
                FROM pg_partitions
            ) THEN 'PARENT'
            ELSE 'REGULAR'
        END AS table_type
    FROM pg_tables
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
)
SELECT 
    pi.table_type,
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    con.convalidated AS is_validated,
    CASE 
        WHEN con.convalidated THEN '✅ VALID'
        ELSE '❌ INVALID'
    END AS validation_status,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
LEFT JOIN partition_info pi ON pi.schemaname = n.nspname AND pi.tablename = c.relname
WHERE con.contype IN ('f', 'c', 'u', 'p')  -- All constraint types
  AND n.nspname NOT IN ('information_schema', 'pg_catalog')
ORDER BY 
    pi.table_type,
    n.nspname, 
    c.relname,
    con.convalidated,  -- Show invalid ones first
    con.conname;

    -- 


    -- Check constraints between specific parent and child tables
-- Replace 'your_parent_table' and 'your_child_table' with actual names

SELECT 
    'PARENT TABLE' AS table_role,
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.convalidated AS is_validated,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid  
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relname = 'your_parent_table'  -- Replace with your parent table
  AND con.contype = 'f'

UNION ALL

SELECT 
    'CHILD TABLE' AS table_role,
    n.nspname AS schema_name, 
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.convalidated AS is_validated,
    pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid  
WHERE c.relname LIKE 'your_child_table%'  -- Pattern match for partitions
  AND con.contype = 'f'
ORDER BY table_role, table_name, constraint_name;

-- 


Index - 

-- Check for invalid indexes (should return 0 rows if all are healthy)
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef,
    CASE 
        WHEN indisvalid THEN '✅ VALID'
        ELSE '❌ INVALID - NEEDS REBUILD'
    END AS index_status
FROM pg_indexes pi
JOIN pg_class c ON pi.indexname = c.relname
JOIN pg_index i ON c.oid = i.indexrelid
WHERE NOT indisvalid  -- Only invalid indexes
  AND schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY schemaname, tablename, indexname;

--


-- Comprehensive index status for all tables
SELECT 
    pi.schemaname,
    pi.tablename,
    pi.indexname,
    CASE 
        WHEN i.indisunique THEN 'UNIQUE'
        WHEN i.indisprimary THEN 'PRIMARY KEY'
        WHEN array_length(i.indkey, 1) = 1 THEN 'SINGLE COLUMN'
        ELSE 'MULTI COLUMN'
    END AS index_type,
    CASE 
        WHEN i.indisvalid THEN '✅ VALID'
        ELSE '❌ INVALID'
    END AS validity_status,
    CASE 
        WHEN i.indisready THEN '✅ READY'
        ELSE '❌ NOT READY'
    END AS ready_status,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    pg_stat_get_tuples_returned(c.oid) AS times_used,
    pg_stat_get_tuples_fetched(c.oid) AS tuples_fetched,
    pi.indexdef AS index_definition
FROM pg_indexes pi
JOIN pg_class c ON pi.indexname = c.relname
JOIN pg_index i ON c.oid = i.indexrelid
JOIN pg_stat_user_indexes psui ON psui.indexrelid = c.oid
WHERE pi.schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY 
    pi.schemaname, 
    pi.tablename,
    CASE WHEN i.indisvalid THEN 1 ELSE 0 END,  -- Invalid indexes first
    pi.indexname;

    ----


    -- Index usage statistics to identify unused indexes
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    CASE 
        WHEN idx_scan = 0 THEN '⚠️ UNUSED INDEX'
        WHEN idx_scan < 100 THEN '🔸 LOW USAGE'
        WHEN idx_scan < 1000 THEN '🔹 MODERATE USAGE'
        ELSE '✅ HIGH USAGE'
    END AS usage_level,
    pg_stat_get_tuples_returned(indexrelid) AS index_scans
FROM pg_stat_user_indexes
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY 
    schemaname, 
    tablename,
    idx_scan ASC;  -- Unused indexes first

    --


    -- Index status specifically for partitioned tables and their partitions
WITH partition_hierarchy AS (
    SELECT 
        schemaname,
        tablename,
        'PARENT' as table_type
    FROM pg_tables pt
    WHERE EXISTS (
        SELECT 1 FROM pg_partitioned_table ppt 
        JOIN pg_class pc ON ppt.partrelid = pc.oid
        JOIN pg_namespace pn ON pc.relnamespace = pn.oid
        WHERE pn.nspname = pt.schemaname AND pc.relname = pt.tablename
    )
    
    UNION ALL
    
    SELECT 
        schemaname,
        tablename,
        'PARTITION' as table_type
    FROM pg_tables pt
    WHERE EXISTS (
        SELECT 1 FROM pg_inherits pi
        JOIN pg_class child ON pi.inhrelid = child.oid
        JOIN pg_namespace child_ns ON child.relnamespace = child_ns.oid
        WHERE child_ns.nspname = pt.schemaname AND child.relname = pt.tablename
    )
)
SELECT 
    ph.table_type,
    pi.schemaname,
    pi.tablename,
    pi.indexname,
    CASE 
        WHEN i.indisvalid THEN '✅ VALID'
        ELSE '❌ INVALID'
    END AS validity_status,
    CASE 
        WHEN i.indisready THEN '✅ READY'
        ELSE '❌ BUILDING'
    END AS ready_status,
    CASE 
        WHEN i.indisprimary THEN 'PRIMARY KEY'
        WHEN i.indisunique THEN 'UNIQUE'
        WHEN i.indisexclusion THEN 'EXCLUSION'
        ELSE 'REGULAR'
    END AS index_type,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    psi.idx_scan AS usage_count,
    pi.indexdef
FROM partition_hierarchy ph
JOIN pg_indexes pi ON ph.schemaname = pi.schemaname AND ph.tablename = pi.tablename
JOIN pg_class c ON pi.indexname = c.relname
JOIN pg_index i ON c.oid = i.indexrelid
LEFT JOIN pg_stat_user_indexes psi ON psi.indexrelid = c.oid
ORDER BY 
    ph.table_type,
    pi.schemaname,
    pi.tablename,
    CASE WHEN i.indisvalid THEN 1 ELSE 0 END,  -- Invalid first
    pi.indexname;

    -- 


    -- Ask for schema and table dynamically
-- (You can pass them in psql: \set schema_name 'public'  \set table_name 'orders')

WITH partition_hierarchy AS (
    SELECT 
        pt.schemaname,
        pt.tablename,
        'PARENT' as table_type
    FROM pg_tables pt
    WHERE pt.schemaname = :'schema_name' 
      AND pt.tablename = :'table_name'
      AND EXISTS (
        SELECT 1 
        FROM pg_partitioned_table ppt 
        JOIN pg_class pc ON ppt.partrelid = pc.oid
        JOIN pg_namespace pn ON pc.relnamespace = pn.oid
        WHERE pn.nspname = pt.schemaname 
          AND pc.relname = pt.tablename
    )
    
    UNION ALL
    
    SELECT 
        pt.schemaname,
        pt.tablename,
        'PARTITION' as table_type
    FROM pg_tables pt
    WHERE pt.schemaname = :'schema_name'
      AND EXISTS (
        SELECT 1 
        FROM pg_inherits pi
        JOIN pg_class child ON pi.inhrelid = child.oid
        JOIN pg_namespace child_ns ON child.relnamespace = child_ns.oid
        JOIN pg_class parent ON pi.inhparent = parent.oid
        JOIN pg_namespace parent_ns ON parent.relnamespace = parent_ns.oid
        WHERE child_ns.nspname = pt.schemaname 
          AND parent_ns.nspname = :'schema_name'
          AND parent.relname = :'table_name'
          AND child.relname = pt.tablename
    )
)
SELECT 
    ph.table_type,
    pi.schemaname,
    pi.tablename,
    pi.indexname,
    CASE 
        WHEN i.indisvalid THEN '✅ VALID'
        ELSE '❌ INVALID'
    END AS validity_status,
    CASE 
        WHEN i.indisready THEN '✅ READY'
        ELSE '❌ BUILDING'
    END AS ready_status,
    CASE 
        WHEN i.indisprimary THEN 'PRIMARY KEY'
        WHEN i.indisunique THEN 'UNIQUE'
        WHEN i.indisexclusion THEN 'EXCLUSION'
        ELSE 'REGULAR'
    END AS index_type,
    pg_size_pretty(pg_relation_size(c.oid)) AS index_size,
    COALESCE(psi.idx_scan, 0) AS usage_count,
    pi.indexdef
FROM partition_hierarchy ph
JOIN pg_indexes pi 
  ON ph.schemaname = pi.schemaname 
 AND ph.tablename = pi.tablename
JOIN pg_class c ON pi.indexname = c.relname
JOIN pg_index i ON c.oid = i.indexrelid
LEFT JOIN pg_stat_user_indexes psi ON psi.indexrelid = c.oid
ORDER BY 
    ph.table_type,
    pi.schemaname,
    pi.tablename,
    CASE WHEN i.indisvalid THEN 1 ELSE 0 END,  -- Invalid first
    pi.indexname;

