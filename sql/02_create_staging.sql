-- ACA Northwind Capstone | 02_create_staging.sql
-- Run while connected to northwind_capstone, not postgres.
-- Source CSVs have no explicit native SQL types; TEXT keeps all source characters,
-- including literal NULL tokens, leading zeroes, and original timestamp formatting.
-- Column names/case and the number of fields match the uploaded CSVs exactly.
-- Do not modify raw values in stg; normalize/CAST when loading dw.

BEGIN;
CREATE SCHEMA IF NOT EXISTS stg;

CREATE TABLE IF NOT EXISTS stg."categories" (
    "categoryID" TEXT,
    "categoryName" TEXT,
    "description" TEXT,
    "picture" TEXT
);

CREATE TABLE IF NOT EXISTS stg."customers" (
    "customerID" TEXT,
    "companyName" TEXT,
    "contactName" TEXT,
    "contactTitle" TEXT,
    "address" TEXT,
    "city" TEXT,
    "region" TEXT,
    "postalCode" TEXT,
    "country" TEXT,
    "phone" TEXT,
    "fax" TEXT
);

CREATE TABLE IF NOT EXISTS stg."employee_territories" (
    "employeeID" TEXT,
    "territoryID" TEXT
);

CREATE TABLE IF NOT EXISTS stg."employees" (
    "employeeID" TEXT,
    "lastName" TEXT,
    "firstName" TEXT,
    "title" TEXT,
    "titleOfCourtesy" TEXT,
    "birthDate" TEXT,
    "hireDate" TEXT,
    "address" TEXT,
    "city" TEXT,
    "region" TEXT,
    "postalCode" TEXT,
    "country" TEXT,
    "homePhone" TEXT,
    "extension" TEXT,
    "photo" TEXT,
    "notes" TEXT,
    "reportsTo" TEXT,
    "photoPath" TEXT
);

CREATE TABLE IF NOT EXISTS stg."order_details" (
    "orderID" TEXT,
    "productID" TEXT,
    "unitPrice" TEXT,
    "quantity" TEXT,
    "discount" TEXT
);

CREATE TABLE IF NOT EXISTS stg."orders" (
    "orderID" TEXT,
    "customerID" TEXT,
    "employeeID" TEXT,
    "orderDate" TEXT,
    "requiredDate" TEXT,
    "shippedDate" TEXT,
    "shipVia" TEXT,
    "freight" TEXT,
    "shipName" TEXT,
    "shipAddress" TEXT,
    "shipCity" TEXT,
    "shipRegion" TEXT,
    "shipPostalCode" TEXT,
    "shipCountry" TEXT
);

CREATE TABLE IF NOT EXISTS stg."products" (
    "productID" TEXT,
    "productName" TEXT,
    "supplierID" TEXT,
    "categoryID" TEXT,
    "quantityPerUnit" TEXT,
    "unitPrice" TEXT,
    "unitsInStock" TEXT,
    "unitsOnOrder" TEXT,
    "reorderLevel" TEXT,
    "discontinued" TEXT
);

CREATE TABLE IF NOT EXISTS stg."regions" (
    "regionID" TEXT,
    "regionDescription" TEXT
);

CREATE TABLE IF NOT EXISTS stg."shippers" (
    "shipperID" TEXT,
    "companyName" TEXT,
    "phone" TEXT
);

CREATE TABLE IF NOT EXISTS stg."suppliers" (
    "supplierID" TEXT,
    "companyName" TEXT,
    "contactName" TEXT,
    "contactTitle" TEXT,
    "address" TEXT,
    "city" TEXT,
    "region" TEXT,
    "postalCode" TEXT,
    "country" TEXT,
    "phone" TEXT,
    "fax" TEXT,
    "homePage" TEXT
);

CREATE TABLE IF NOT EXISTS stg."territories" (
    "territoryID" TEXT,
    "territoryDescription" TEXT,
    "regionID" TEXT
);

COMMIT;

-- Validation: expect 11 staging tables (once this script has run).
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'stg' AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Source CSV rows will be loaded later by Python; these tables start empty.
