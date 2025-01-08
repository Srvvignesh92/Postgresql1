CREATE OR REPLACE PROCEDURE GET_TABLE_COLUMNS
AS
    CURSOR column_cursor IS
        SELECT owner, table_name, column_name, data_type
        FROM all_tab_columns
        WHERE data_type NOT IN ('LONG', 'CLOB', 'DATE', 'TIMESTAMP')
        ORDER BY owner, table_name, column_name;

    -- Variable to hold cursor data
    column_rec column_cursor%ROWTYPE;

    -- Variable to hold dynamic SQL
    v_sql VARCHAR2(1000);

    -- Variable to hold the count of rows
    v_row_count NUMBER;
BEGIN
    -- Loop through each column from the cursor
    FOR column_rec IN column_cursor LOOP
        BEGIN
            -- Construct the dynamic SQL query
            v_sql := 'SELECT COUNT(*) FROM ' || column_rec.owner || '.' || column_rec.table_name || 
                     ' WHERE ' || column_rec.column_name || ' IS NOT NULL';

            -- Execute the query and store the result in v_row_count
            EXECUTE IMMEDIATE v_sql INTO v_row_count;

            -- Check the count and take appropriate action
            IF v_row_count > 1 THEN
                -- Insert into the staging table
                INSERT INTO staging_table (owner, table_name, record_count)
                VALUES (column_rec.owner, column_rec.table_name, v_row_count);

                -- Optional: Log a message for successful insert
                DBMS_OUTPUT.PUT_LINE('Inserted into staging: Owner: ' || column_rec.owner || 
                                     ', Table: ' || column_rec.table_name || 
                                     ', Non-NULL Rows: ' || v_row_count);
            ELSIF v_row_count = 0 THEN
                -- Log a message that no rows were observed
                DBMS_OUTPUT.PUT_LINE('No rows observed for Table: ' || column_rec.owner || '.' || column_rec.table_name);
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                -- Handle exceptions, e.g., if the table does not exist or is inaccessible
                DBMS_OUTPUT.PUT_LINE('Error processing Table: ' || column_rec.table_name || 
                                     ', Column: ' || column_rec.column_name || 
                                     ' - ' || SQLERRM);
        END;
    END LOOP;
END GET_TABLE_COLUMNS;
/
