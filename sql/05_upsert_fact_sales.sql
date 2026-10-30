-- ACA Data Analytics Capstone | 05_upsert_fact_sales.sql
-- Target database: northwind_capstone (PostgreSQL)
-- Prerequisites:
--   stg.orders (830 rows) and stg.order_details (2,155 rows) are loaded.
--   dw.dim_customer (91), dim_product (77), dim_employee (9),
--   dim_shipper (3) and dim_date (1990-01-01 .. 9999-12-31) are loaded.
-- Grain: ONE row per (order_id, product_sk), from each order/product line.
-- Source price comes from stg.order_details.unitPrice, not list price.
-- No procedural DO/PLPGSQL block: ordinary PostgreSQL SQL only.
-- Existing sales_sk values are preserved on repeat UPSERT runs.
-- Amounts: gross = unit price * quantity; net = gross after discount,
-- rounded to cents per line; discount_amount = gross - net.
-- Excludes order-level freight to avoid duplicating freight over order lines.

-- A pre-load integrity check (all missing_* must be zero for this dataset).
SELECT
    COUNT(*) AS source_order_lines,
    COUNT(*) FILTER (WHERE o."orderID" IS NULL) AS missing_orders,
    COUNT(*) FILTER (WHERE c.customer_sk IS NULL) AS missing_customers,
    COUNT(*) FILTER (WHERE p.product_sk IS NULL) AS missing_products,
    COUNT(*) FILTER (WHERE dt.date_sk IS NULL) AS missing_order_dates
FROM stg.order_details AS od
LEFT JOIN stg.orders AS o
  ON o."orderID" = od."orderID"
LEFT JOIN dw.dim_customer AS c
  ON c.customer_id = o."customerID"
LEFT JOIN dw.dim_product AS p
  ON p.product_id = od."productID"::INTEGER
LEFT JOIN dw.dim_date AS dt
  ON dt.full_date = NULLIF(NULLIF(BTRIM(o."orderDate"), ''), 'NULL')::TIMESTAMP::DATE;

BEGIN;

WITH source_lines AS (
    SELECT
        od."orderID"::INTEGER AS order_id,
        o."customerID" AS customer_id,
        od."productID"::INTEGER AS product_id,
        NULLIF(NULLIF(BTRIM(o."employeeID"), ''), 'NULL')::INTEGER AS employee_id,
        NULLIF(NULLIF(BTRIM(o."shipVia"), ''), 'NULL')::INTEGER AS shipper_id,
        NULLIF(NULLIF(BTRIM(o."orderDate"), ''), 'NULL')::TIMESTAMP::DATE AS order_date,
        NULLIF(NULLIF(BTRIM(o."requiredDate"), ''), 'NULL')::TIMESTAMP::DATE AS required_date,
        NULLIF(NULLIF(BTRIM(o."shippedDate"), ''), 'NULL')::TIMESTAMP::DATE AS shipped_date,
        NULLIF(NULLIF(BTRIM(o."shipCity"), ''), 'NULL') AS ship_city,
        NULLIF(NULLIF(BTRIM(o."shipCountry"), ''), 'NULL') AS ship_country,
        od."unitPrice"::NUMERIC(12,2) AS unit_price,
        od."quantity"::INTEGER AS quantity,
        od."discount"::NUMERIC(5,4) AS discount_rate
    FROM stg.order_details AS od
    JOIN stg.orders AS o ON o."orderID" = od."orderID"
),
calculated AS (
    SELECT
        s.*,
        ROUND(s.unit_price * s.quantity, 2) AS gross_sales,
        ROUND(s.unit_price * s.quantity * (1 - s.discount_rate), 2) AS net_sales
    FROM source_lines AS s
)
INSERT INTO dw.fact_sales (
    order_id, customer_sk, product_sk, employee_sk, shipper_sk,
    order_date_sk, required_date, shipped_date, ship_city, ship_country,
    unit_price, quantity, discount_rate, gross_sales, discount_amount, net_sales
)
SELECT
    l.order_id,
    c.customer_sk,
    p.product_sk,
    e.employee_sk,
    sh.shipper_sk,
    dt.date_sk,
    l.required_date,
    l.shipped_date,
    l.ship_city,
    l.ship_country,
    l.unit_price,
    l.quantity,
    l.discount_rate,
    l.gross_sales,
    l.gross_sales - l.net_sales AS discount_amount,
    l.net_sales
FROM calculated AS l
LEFT JOIN dw.dim_customer AS c ON c.customer_id = l.customer_id
LEFT JOIN dw.dim_product AS p ON p.product_id = l.product_id
LEFT JOIN dw.dim_employee AS e ON e.employee_id = l.employee_id
LEFT JOIN dw.dim_shipper AS sh ON sh.shipper_id = l.shipper_id
LEFT JOIN dw.dim_date AS dt ON dt.full_date = l.order_date
WHERE TRUE  -- Separates SELECT from ON CONFLICT for PostgreSQL parser.
ON CONFLICT (order_id, product_sk) DO UPDATE SET
    customer_sk     = EXCLUDED.customer_sk,
    employee_sk     = EXCLUDED.employee_sk,
    shipper_sk      = EXCLUDED.shipper_sk,
    order_date_sk   = EXCLUDED.order_date_sk,
    required_date   = EXCLUDED.required_date,
    shipped_date    = EXCLUDED.shipped_date,
    ship_city       = EXCLUDED.ship_city,
    ship_country    = EXCLUDED.ship_country,
    unit_price      = EXCLUDED.unit_price,
    quantity        = EXCLUDED.quantity,
    discount_rate   = EXCLUDED.discount_rate,
    gross_sales     = EXCLUDED.gross_sales,
    discount_amount = EXCLUDED.discount_amount,
    net_sales       = EXCLUDED.net_sales;

COMMIT;

-- Check expected: 2,155 lines, 2,155 unique order/product pairs;
-- financial totals from the original provided 11 Northwind CSVs:
-- gross_sales=1,354,458.59; discount_amount=88,665.30; net_sales=1,265,793.29.
SELECT
    COUNT(*) AS fact_rows,
    COUNT(DISTINCT (order_id, product_sk)) AS unique_order_product_pairs,
    COUNT(DISTINCT order_id) AS orders_count,
    SUM(gross_sales) AS gross_sales,
    SUM(discount_amount) AS discount_amount,
    SUM(net_sales) AS net_sales,
    CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM stg.order_details)
      THEN 'PASS' ELSE 'FAIL' END AS row_count_status
FROM dw.fact_sales;

-- Re-run the entire script to verify no duplicate rows appear.
-- Expect COUNT(*)=2,155 again, with the same totals; subsequent validation
-- should also compare sales_sk values and exact row content.
