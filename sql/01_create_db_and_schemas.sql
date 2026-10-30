-- ACA Capstone / PostgreSQL / Step 01
-- RUN SECTION A while connected to an EXISTING database such as 'postgres'.
-- PostgreSQL CREATE DATABASE must be executed outside a transaction block.
-- In DBeaver, execute only the CREATE DATABASE statement (Ctrl+Enter).

CREATE DATABASE northwind_capstone;

-- SECTION B: after SECTION A, create/reconnect a DBeaver SQL editor
-- that is connected to database 'northwind_capstone'.
-- Execute the following statements in that editor.

CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS dw;

-- Validation. Expected: two rows: dw and stg.
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('stg', 'dw')
ORDER BY schema_name;

-- Database validation: should return northwind_capstone.
SELECT current_database();
