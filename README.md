# ACA Data Analytics Capstone — Northwind Traders

**End-to-end analytics pipeline: Northwind CSV → PostgreSQL Staging → Data Warehouse → Python Statistical Analysis → Power BI**

This project transforms the classic Northwind Traders transactional data into a reproducible PostgreSQL star schema, validates data quality, investigates business questions with Python, and presents an interactive four-page Power BI management dashboard.

> **Project status (30 October 2026):** PostgreSQL ETL, warehouse validation, Jupyter statistical analysis, and the four-page Power BI report are completed on the development machine. The report has been saved as `reports/northwind_executive_dashboard.pbix` (reported by the developer); GitHub publication and an independent audit of the final repository contents are still pending. This source has **11 CSV tables** although the ACA assignment specifies **13**; the source discrepancy remains documented.

## 1. Technology stack

- **Database:** PostgreSQL (`northwind_capstone`), SQL, staging schema (`stg`), analytics schema (`dw`)
- **ETL:** Python, Pandas, SQLAlchemy, psycopg2
- **Analysis:** JupyterLab, Pandas, NumPy, Matplotlib
- **Reporting:** Power BI Desktop, Power Query M, DAX (four analytical report pages)
- **Development tools:** DBeaver, PowerShell, Git/GitHub (**final repository publication pending**)

## 2. Repository structure

```text
northwind-capstone-pipeline/
├── .gitignore
├── README.md
├── requirements.txt
├── run_pipeline.py
├── data/
│   └── raw/                       # 11 Northwind CSVs used by this project
├── sql/
│   ├── 01_create_db_and_schemas.sql
│   ├── 02_create_staging.sql
│   ├── 03_create_warehouse.sql
│   ├── 04_upsert_dimensions.sql
│   └── 05_upsert_fact_sales.sql
├── src/
│   ├── __init__.py
│   ├── config.py
│   ├── db_connector.py
│   ├── extract_raw_data.py
│   ├── stage_raw_data.py
│   └── transform_warehouse.py
├── notebooks/
│   ├── etl_development.ipynb       # Development/testing notebook, if retained
│   └── statistical_analysis.ipynb # EDA, KPIs, statistical tests, charts
└── reports/
    └── northwind_executive_dashboard.pbix  # Completed report; verify included in repository
```

The developer reports saving the final PBIX to `reports/`; confirm that this file and the other paths above are actually present before publishing. Python-generated `__pycache__/` directories are **not** project deliverables and should be excluded by `.gitignore`.

## 3. Source data and known gap

The current pipeline processes these **11 CSVs**:

`categories`, `customers`, `employee_territories`, `employees`, `order_details`, `orders`, `products`, `regions`, `shippers`, `suppliers`, `territories`.

- **Source rows loaded into `stg`: 3,308** across 11 tables.
- The automated source-download module uses a public Northwind CSV repository; existing local files are reused by default.
- **Assignment discrepancy:** the ACA brief calls for **13** raw CSV tables. This implementation has only the 11 files provided/verified for the selected source. It should **not** be described as meeting the 13-file requirement without approval or additional verified source tables.
- Do not fabricate data for missing tables. Any later source additions should be documented and tested against the ETL and staging schema.

## 4. Architecture and warehouse model

```text
Northwind CSV files (11)
          |
          v
Python extraction / source verification
          |
          v
PostgreSQL stg schema (raw, one-to-one TEXT columns)
          |
          v
SQL transformations + idempotent UPSERT
          |
          v
PostgreSQL dw schema (star schema)
          |                         |
          v                         v
Jupyter EDA & inference       Power BI (4 report pages)
```

**Fact grain:** one row per `(order_id, product_sk)` in `dw.fact_sales` (one product line within an order).

**Dimension tables:**

- `dw.dim_customer` — customers, location and contact details
- `dw.dim_product` — product, category and supplier attributes (flattened)
- `dw.dim_employee` — employee attributes
- `dw.dim_shipper` — shipper attributes
- `dw.dim_date` — independent calendar from **1990-01-01 through 9999-12-31**

The fact links to dimensions using surrogate keys (`*_sk`). The full PostgreSQL calendar `dw.dim_date` has **2,925,592** dates and remains in the database to satisfy the warehouse specification. In the Power BI semantic model, a much smaller `DimDate_M` calendar is generated using Power Query M for the relevant analysis period, with a `YYYYMMDD` key. The fact table includes a matching `order_date_sk_fk` model column; the active date relationship joins `dw fact_sales[order_date_sk_fk]` to `DimDate_M[Date_Id_PK_SK]` (many-to-one, single-direction). The imported multi-million-row date table is not needed in the report model.

**Revenue definitions (each fact row):**

```text
gross_sales     = unit_price * quantity
discount_amount = gross_sales - net_sales
net_sales       = round(unit_price * quantity * (1 - discount_rate), 2)
```

Financial measures are rounded to cents per sales line in the warehouse. Order-level shipping freight is not repeated across sales lines, to avoid double counting.

## 5. Setup and running the ETL

### Prerequisites

- Python 3 and PostgreSQL installed and running
- PostgreSQL login permitted to connect to and, if necessary, create `northwind_capstone`
- Project files kept together in the directory structure above

Open **PowerShell in the project root** (the folder containing `run_pipeline.py`), then run:

```powershell
python -m pip install -r requirements.txt
python run_pipeline.py
```

At the prompt, enter the PostgreSQL password. Password input may be **invisible** in the terminal; type it and press Enter. **Never write passwords into the README, notebook, source code, or GitHub.**

By default the scripts use:

| Setting | Value |
|---|---|
| PostgreSQL host | `localhost` |
| Port | `5432` |
| Database | `northwind_capstone` |
| User | `postgres` |

The values can be overridden using the environment variables `CAPSTONE_DB_HOST`, `CAPSTONE_DB_PORT`, `CAPSTONE_DB_NAME`, and `CAPSTONE_DB_USER`. A `CAPSTONE_DB_PASSWORD` environment variable is supported but should not be committed or shared.

The CLI uses PostgreSQL's maintenance database to create `northwind_capstone` **only when missing**. The standalone `sql/01_create_db_and_schemas.sql` documents/manual-creates the database and must **not** be blindly rerun after the database already exists. The orchestrator runs the staging and warehouse SQL scripts in the necessary order.

**ETL stages:**

1. Check/download the expected 11 CSVs if missing.
2. Create or confirm `stg` tables.
3. Replace raw staging rows transactionally, preserving raw values.
4. Create or confirm `dw` tables and the date dimension.
5. UPSERT business dimensions, then fact sales.
6. Validate row counts, uniqueness and foreign-key coverage.

To explicitly re-download the 11 CSV files (internet required):

```powershell
python run_pipeline.py --refresh-source
```

Use this option carefully: it **overwrites local CSVs** with the source's current versions. Ordinary `python run_pipeline.py` keeps existing files and is the preferred reproducibility check.

## 6. Validated warehouse results

The following figures were observed on the development database after successful pipeline runs and cross-checked in the Jupyter analysis:

| Metric | Verified result |
|---|---:|
| Staging tables | 11 |
| Total staging rows | 3,308 |
| Fact sales rows | 2,155 |
| Distinct orders | 830 |
| Customer dimension rows | 91 |
| Product dimension rows | 77 |
| Employee dimension rows | 9 |
| Shipper dimension rows | 3 |
| Date dimension rows | 2,925,592 |
| Gross sales | 1,354,458.59 |
| Total discounts | 88,665.30 |
| **Net sales** | **1,265,793.29** |
| Average order value (AOV) | 1,525.05 |

A repeated-run check produced the same fact-row totals and matching fact snapshot hash. The analysis also found **0 duplicate `(order_id, product_sk)` keys** and **0 financial inconsistencies** (tolerance: 0.01 per row). These checks establish repeatability for the tested input; other source versions and environments still require validation.

## 7. EDA and statistical hypotheses

Notebook: `notebooks/statistical_analysis.ipynb`

The notebook connects to `dw.fact_sales` and `dw.dim_date` to inspect data types, missing data, distinct orders, revenue, average order value, monthly/yearly revenue, discounts, shipping dates, and regional order patterns. It includes a monthly revenue chart and two bootstrap distribution charts.

**Data interpretation notes:**

- Order dates span **1996-07-04 to 1998-05-06**. The first and final calendar months are incomplete; the monthly revenue chart excludes these months for fairer visual comparison.
- **21 orders** (73 sales lines) have no shipped date. This represents missing shipment information, not automatically a proven operational failure.
- Revenue is **not** the same as profit: costs are not included.

### Hypothesis 1 — discounts vs order quantity

- **Question:** Do orders containing at least one discounted product have different average unit quantities from orders with no discounts?
- **H0:** Mean order quantity is equal across the two groups.
- **H1:** Mean order quantity differs.
- **Method:** Two-sided permutation test (5,000 permutations), plus bootstrap 95% confidence interval (5,000 resamples).
- **Without discount:** 450 orders, average **52.44** units/order.
- **With discount:** 380 orders, average **72.94** units/order.
- **Observed difference:** **+20.50** units/order (discounted minus non-discounted).
- **P-value:** **0.0002**; **bootstrap 95% CI:** **[13.63, 27.42]** units.
- **Finding:** A statistically significant difference was detected at the 5% level in this exploratory comparison.
- **Recommendation:** Investigate discount eligibility and order size before changing promotion policy. Larger orders may naturally be more likely to contain at least one discounted item. **Association does not demonstrate causation.**

### Hypothesis 2 — USA vs Germany average order value

- **Question:** Is the mean order value different between orders shipped to the USA and Germany?
- **H0:** Equal mean order values.
- **H1:** Different mean order values.
- **Method:** Two-sided permutation test (5,000 permutations), plus bootstrap 95% confidence interval (5,000 resamples).
- **USA:** 122 orders, AOV **2,012.99**.
- **Germany:** 122 orders, AOV **1,887.58**.
- **Observed difference:** **+125.41** (USA minus Germany).
- **P-value:** **0.6845**; **bootstrap 95% CI:** **[-475.99, 711.56]**.
- **Finding:** No statistically significant difference was detected at the 5% level. This **does not prove the two population means are equal**.
- **Recommendation:** Avoid prioritizing either country solely because of the observed AOV difference. Evaluate demand, margin, and customer-level behavior as well.

**Statistical limitations:** tests treat orders as independent even though a customer may place multiple orders; promotional assignments were not randomized; these are observational analyses. Both comparisons are exploratory, and results should be interpreted with those limitations.

### Reproducing the notebook

1. Ensure PostgreSQL and `northwind_capstone` are running and the ETL has populated `dw`.
2. Start JupyterLab: `jupyter lab`.
3. Open `notebooks/statistical_analysis.ipynb`.
4. **After any kernel restart**, run the password-widget cell **before** the database-connection cell; enter the password in the widget, then run the connection cell.
5. Execute the remaining analysis cells in order, checking for errors.

The password is cleared from the interactive widget after the connection attempt. Jupyter execution counts may differ from physical cell order; the correct run order is top to bottom.

## 8. Power BI — implemented

**Deliverable:** `reports/northwind_executive_dashboard.pbix` (saved locally; confirm file is included in the final GitHub repository).

The report imports the PostgreSQL `dw` fact and business dimensions into Power BI and uses a separate Power Query M date table, `DimDate_M`, for efficient filtering and time calculations. The report model was checked in Power BI Model view:

- `dw fact_sales` on the many side of five active, single-direction, many-to-one relationships to customers, products, employees, shippers, and `DimDate_M`.
- `DimDate_M` is marked as a date table using its actual `Date` column; its `Date_Id_PK_SK` key links to `dw fact_sales[order_date_sk_fk]`.
- Explicit DAX measures are grouped in `_Measures`. A disconnected `KPI Selector` field parameter switches the monthly trend between Revenue, Orders, and Quantity.
- The model also contains a calculated `Customer_Performance` table and date-related calculated columns.

### Report pages

| Page | Main content and interactions |
|---|---|
| `01 - Sales Overview` | Revenue, average order value, orders and discount-rate KPI cards; monthly trend with a dynamic metric selector; top 10 countries by revenue; Year and product-category slicers. |
| `02 - Product Performance` | Units sold, unique products sold, revenue KPI cards; top 10 products by revenue; revenue by product category (treemap); Year and category slicers with cross-filtering. |
| `03 - Customer Analysis` | Active customers, AOV and revenue cards; top 10 customers by revenue; customer-performance matrix containing orders, AOV and revenue with conditional data bars; Year slicer. |
| `04 - Shipping & Operations` | Average days from order to shipment, unshipped orders, shipped orders and on-time shipment rate; stacked bar comparing on-time and late shipments by shipper; Year slicer. |

### Reconciliation and data interpretation

- **Net sales:** 1,265,793.29; **distinct orders:** 830; **active customers:** 89. The revenue total was reconciled against the PostgreSQL warehouse.
- **Shipped orders:** 809 = **772 on-time** + **37 late** (verified using a Power BI validation table); **unshipped orders:** 21. **On-time shipping rate:** 95.43%.
- `shipped_date` is the **shipment** date, not proof of delivery to the customer; "on time" here means `shipped_date <= required_date` for orders with both dates.
- Sales history runs from **4 July 1996 through 6 May 1998**. May 1998 is only a partial month and is annotated on the monthly chart.
- `Previous Year Revenue` and `YoY Growth %` are implemented for time analysis. Annual comparisons must be interpreted cautiously: 1996 and 1998 are incomplete years, and a full-year comparison with those years is not like-for-like. In the validation table the 1997 YoY is 196.56% mathematically, but it compares full 1997 against a partial 1996; avoid presenting that as representative business growth. The report's YoY measure suppresses some incomplete periods.

The model and report-page interactions were checked visually during development; source-file presence, end-to-end opening from a clean machine, and GitHub publication still require a final submission check.

## 9. Final delivery checklist

- [x] PostgreSQL database, schemas and repeatable SQL loading
- [x] Automated Python ETL tested with the available 11 CSVs
- [x] Warehouse data-quality checks and fact-level reconciliation
- [x] Jupyter EDA, business KPIs, two formal statistical hypotheses, confidence intervals and charts
- [x] Four Power BI report pages, DAX measures, calculated model objects, slicers and a field parameter
- [x] Power BI star-schema relationships, date table and core KPI reconciliation checked
- [x] Final Power BI report saved locally in `reports/` (developer confirmation)
- [x] Document 11-source-versus-13-assignment discrepancy in README
- [ ] Confirm whether the 11-source limitation is accepted by the instructor or whether additional inputs are required
- [ ] Check that `.gitignore`, code, notebooks, CSVs, requirements and PBIX all exist in the expected locations
- [ ] Publish/refresh the GitHub repository and inspect the published file list
- [ ] Submit the final repository link and any other deliverables required by ACA

## 10. Security and reproducibility

Do not commit passwords, `.env` files, virtual environments, Jupyter checkpoints, `__pycache__`, or personal connection credentials. Preserve the original CSVs used for validation. The pipeline is intended to be rerunnable against the same source files; always recheck record counts and financial totals after changing the data or SQL.
