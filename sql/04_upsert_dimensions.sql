-- ACA Capstone | 04_upsert_dimensions.sql
-- Database: northwind_capstone | PostgreSQL
-- Prerequisites: stg tables loaded (11 Northwind CSVs),
--                dw tables already created by 03_create_warehouse.sql.
-- Loads 4 business dimensions with natural-key UPSERT. Existing surrogate
-- keys (*_sk) are preserved on reruns; the date dimension is populated by 03.
-- Source literal 'NULL' and empty strings become SQL NULL for optional fields.

BEGIN;

-- 1. Customers (91 expected)
INSERT INTO dw.dim_customer (
    customer_id, company_name, contact_name, city, region, country, postal_code
)
SELECT
    c."customerID",
    c."companyName",
    NULLIF(NULLIF(BTRIM(c."contactName"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(c."city"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(c."region"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(c."country"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(c."postalCode"), ''), 'NULL')
FROM stg.customers AS c
WHERE TRUE -- Avoid INSERT ... SELECT / ON CONFLICT parser ambiguity.
ON CONFLICT (customer_id) DO UPDATE SET
    company_name = EXCLUDED.company_name,
    contact_name = EXCLUDED.contact_name,
    city         = EXCLUDED.city,
    region       = EXCLUDED.region,
    country      = EXCLUDED.country,
    postal_code  = EXCLUDED.postal_code;

-- 2. Products (77 expected); flatten categories and suppliers.
-- Use LEFT JOINs because we should not silently discard a product
-- if a category or supplier label is unavailable.
INSERT INTO dw.dim_product (
    product_id, product_name, category_id, category_name,
    supplier_id, supplier_name, quantity_per_unit,
    list_unit_price, discontinued
)
SELECT
    p."productID"::INTEGER,
    p."productName",
    NULLIF(NULLIF(BTRIM(p."categoryID"), ''), 'NULL')::INTEGER,
    NULLIF(NULLIF(BTRIM(c."categoryName"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(p."supplierID"), ''), 'NULL')::INTEGER,
    NULLIF(NULLIF(BTRIM(s."companyName"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(p."quantityPerUnit"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(p."unitPrice"), ''), 'NULL')::NUMERIC(12,2),
    CASE
        WHEN LOWER(BTRIM(p."discontinued")) IN ('1', 'true', 't', 'yes') THEN TRUE
        WHEN LOWER(BTRIM(p."discontinued")) IN ('0', 'false', 'f', 'no') THEN FALSE
        ELSE NULL
    END
FROM stg.products AS p
LEFT JOIN stg.categories AS c
    ON p."categoryID" = c."categoryID"
LEFT JOIN stg.suppliers AS s
    ON p."supplierID" = s."supplierID"
WHERE TRUE
ON CONFLICT (product_id) DO UPDATE SET
    product_name      = EXCLUDED.product_name,
    category_id       = EXCLUDED.category_id,
    category_name     = EXCLUDED.category_name,
    supplier_id       = EXCLUDED.supplier_id,
    supplier_name     = EXCLUDED.supplier_name,
    quantity_per_unit = EXCLUDED.quantity_per_unit,
    list_unit_price   = EXCLUDED.list_unit_price,
    discontinued      = EXCLUDED.discontinued;

-- 3. Employees (9 expected)
INSERT INTO dw.dim_employee (
    employee_id, first_name, last_name, job_title, hire_date, city, country
)
SELECT
    e."employeeID"::INTEGER,
    NULLIF(NULLIF(BTRIM(e."firstName"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(e."lastName"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(e."title"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(e."hireDate"), ''), 'NULL')::TIMESTAMP::DATE,
    NULLIF(NULLIF(BTRIM(e."city"), ''), 'NULL'),
    NULLIF(NULLIF(BTRIM(e."country"), ''), 'NULL')
FROM stg.employees AS e
WHERE TRUE
ON CONFLICT (employee_id) DO UPDATE SET
    first_name = EXCLUDED.first_name,
    last_name  = EXCLUDED.last_name,
    job_title  = EXCLUDED.job_title,
    hire_date  = EXCLUDED.hire_date,
    city       = EXCLUDED.city,
    country    = EXCLUDED.country;

-- 4. Shippers (3 expected)
INSERT INTO dw.dim_shipper (shipper_id, company_name)
SELECT
    sh."shipperID"::INTEGER,
    sh."companyName"
FROM stg.shippers AS sh
WHERE TRUE
ON CONFLICT (shipper_id) DO UPDATE SET
    company_name = EXCLUDED.company_name;

-- No PL/pgSQL DO block here. Some Windows PostgreSQL installations
-- block plpgsql.dll via application-control policy. Standard SQL is enough
-- to populate these dimensions; validate the results with SELECT below.

COMMIT;

-- Post-load verification; the first four rows must be marked PASS.
-- The date dimension and fact table are checked separately.
SELECT 'dim_customer' AS table_name,
       (SELECT COUNT(*) FROM dw.dim_customer) AS actual_rows,
       (SELECT COUNT(*) FROM stg.customers) AS source_rows,
       CASE WHEN (SELECT COUNT(*) FROM dw.dim_customer) = (SELECT COUNT(*) FROM stg.customers)
            THEN 'PASS' ELSE 'FAIL' END AS status
UNION ALL
SELECT 'dim_product',
       (SELECT COUNT(*) FROM dw.dim_product),
       (SELECT COUNT(*) FROM stg.products),
       CASE WHEN (SELECT COUNT(*) FROM dw.dim_product) = (SELECT COUNT(*) FROM stg.products)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'dim_employee',
       (SELECT COUNT(*) FROM dw.dim_employee),
       (SELECT COUNT(*) FROM stg.employees),
       CASE WHEN (SELECT COUNT(*) FROM dw.dim_employee) = (SELECT COUNT(*) FROM stg.employees)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'dim_shipper',
       (SELECT COUNT(*) FROM dw.dim_shipper),
       (SELECT COUNT(*) FROM stg.shippers),
       CASE WHEN (SELECT COUNT(*) FROM dw.dim_shipper) = (SELECT COUNT(*) FROM stg.shippers)
            THEN 'PASS' ELSE 'FAIL' END
ORDER BY table_name;
