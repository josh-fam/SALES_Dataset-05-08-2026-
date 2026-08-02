-- ============================================================
-- Sales Analytics Pipeline — Full SQL Pipeline
-- Postgres | staging -> clean -> final
-- ============================================================

-- ------------------------------------------------------------
-- 1. DATABASE SETUP
-- ------------------------------------------------------------
CREATE DATABASE sales_analysis;
\c sales_analysis

-- Fix for terminal display of non-ASCII characters (e.g. "São Paulo").
-- The underlying data is correctly UTF-8; this only affects what your
-- psql session displays. Run once per session, or ALTER DATABASE below.
SET client_encoding = 'UTF8';
-- ALTER DATABASE sales_analysis SET client_encoding = 'UTF8';  -- persistent, may require reconnect

-- ------------------------------------------------------------
-- 2. STAGING TABLE (all TEXT — raw load, nothing cast yet)
-- ------------------------------------------------------------
CREATE TABLE staging_sales (
    order_id            TEXT,
    transaction_id       TEXT,
    product_name          TEXT,
    category               TEXT,
    sub_category             TEXT,
    quantity_ordered          TEXT,
    unit_price                 TEXT,
    total_sales                  TEXT,
    cost                           TEXT,
    order_date                      TEXT,
    purchase_address                  TEXT,
    sales_channel                       TEXT,
    customer_segment                      TEXT,
    region                                   TEXT,
    city                                        TEXT,
    payment_type                                  TEXT,
    delivery_time_days                              TEXT,
    sales_rep                                         TEXT
);

-- ------------------------------------------------------------
-- 3. LOAD CSV INTO STAGING (adjust file path as needed)
-- ------------------------------------------------------------
\copy staging_sales FROM 'C:/salesproject/sales_dataset_5000_rows.csv' WITH (FORMAT csv, HEADER true)

-- Verify load
SELECT COUNT(*) FROM staging_sales;  -- expect 5000

-- ------------------------------------------------------------
-- 4. PROFILING — evidence gathered BEFORE any cleaning
-- ------------------------------------------------------------

-- Duplicates
SELECT order_id, COUNT(*) FROM staging_sales GROUP BY order_id HAVING COUNT(*) > 1;
SELECT transaction_id, COUNT(*) FROM staging_sales GROUP BY transaction_id HAVING COUNT(*) > 1;

-- Categorical inconsistencies
SELECT DISTINCT category FROM staging_sales ORDER BY category;
SELECT DISTINCT sub_category FROM staging_sales ORDER BY sub_category;
SELECT DISTINCT sales_channel FROM staging_sales ORDER BY sales_channel;
SELECT DISTINCT customer_segment FROM staging_sales ORDER BY customer_segment;
SELECT DISTINCT region FROM staging_sales ORDER BY region;
SELECT DISTINCT payment_type FROM staging_sales ORDER BY payment_type;

-- Missing values
SELECT
    COUNT(*) FILTER (WHERE unit_price IS NULL OR TRIM(unit_price) = '') AS missing_unit_price,
    COUNT(*) FILTER (WHERE delivery_time_days IS NULL OR TRIM(delivery_time_days) = '') AS missing_delivery_time
FROM staging_sales;

-- Zero total_sales (tied to missing unit_price)
SELECT COUNT(*) FROM staging_sales WHERE total_sales::NUMERIC = 0;

-- Date format sample and count of MM/DD/YYYY-formatted rows
SELECT order_date FROM staging_sales LIMIT 20;
SELECT COUNT(*) FROM staging_sales WHERE TRIM(order_date) ~ '^\d{2}/\d{2}/\d{4}';

-- City vs. address mismatch — headline finding
SELECT
    purchase_address,
    city,
    TRIM(SPLIT_PART(purchase_address, ',', 2)) AS address_city
FROM staging_sales
LIMIT 15;

SELECT COUNT(*)
FROM staging_sales
WHERE TRIM(city) != TRIM(SPLIT_PART(purchase_address, ',', 2));  -- 4305 / 5000 (86%)

-- ------------------------------------------------------------
-- 5. CLEAN TABLE — cast, standardize, derive trustworthy city
-- ------------------------------------------------------------
CREATE TABLE clean_sales AS
SELECT
    order_id::INT,
    TRIM(transaction_id) AS transaction_id,
    TRIM(product_name) AS product_name,

    CASE
        WHEN LOWER(TRIM(category)) = 'electronics' THEN 'Electronics'
        ELSE TRIM(category)
    END AS category,

    TRIM(sub_category) AS sub_category,
    quantity_ordered::INT,

    NULLIF(TRIM(unit_price), '')::NUMERIC AS unit_price,
    NULLIF(TRIM(total_sales), '')::NUMERIC AS total_sales,
    NULLIF(TRIM(cost), '')::NUMERIC AS cost,

    -- Two mixed date formats in one column: YYYY-MM-DD and MM/DD/YYYY
    CASE
        WHEN TRIM(order_date) ~ '^\d{2}/\d{2}/\d{4}'
            THEN TO_TIMESTAMP(TRIM(order_date), 'MM/DD/YYYY HH24:MI')::TIMESTAMP
        ELSE
            TO_TIMESTAMP(TRIM(order_date), 'YYYY-MM-DD HH24:MI:SS')::TIMESTAMP
    END AS order_date,

    TRIM(purchase_address) AS purchase_address,
    TRIM(SPLIT_PART(purchase_address, ',', 2)) AS address_city,  -- derived, trustworthy city
    -- original `city` column dropped after being confirmed unreliable in 86% of rows

    TRIM(sales_channel) AS sales_channel,
    TRIM(customer_segment) AS customer_segment,
    TRIM(region) AS region,   -- kept for now; later confirmed unreliable relative to address_city, see step 7
    TRIM(payment_type) AS payment_type,
    NULLIF(TRIM(delivery_time_days), '')::NUMERIC AS delivery_time_days,
    TRIM(sales_rep) AS sales_rep

FROM staging_sales;

SELECT COUNT(*) FROM clean_sales;  -- expect 5000

-- ------------------------------------------------------------
-- 6. POST-CLEAN VERIFICATION
-- ------------------------------------------------------------
SELECT purchase_address FROM clean_sales WHERE purchase_address LIKE '%Paulo%' LIMIT 5;
SELECT DISTINCT category FROM clean_sales;
SELECT MIN(order_date), MAX(order_date) FROM clean_sales;
SELECT address_city, COUNT(*) FROM clean_sales GROUP BY address_city ORDER BY COUNT(*) DESC;
SELECT
    COUNT(*) FILTER (WHERE unit_price IS NULL) AS null_unit_price,
    COUNT(*) FILTER (WHERE delivery_time_days IS NULL) AS null_delivery_time
FROM clean_sales;

-- ------------------------------------------------------------
-- 7. JUDGMENT CALLS
-- ------------------------------------------------------------

-- 7a. Investigate missing pricing data (247 rows) before flagging
SELECT order_id, product_name, category, quantity_ordered, unit_price, total_sales, cost,
       order_date, sales_channel, region
FROM clean_sales
WHERE unit_price IS NULL
LIMIT 20;

SELECT product_name, COUNT(*) FROM clean_sales WHERE unit_price IS NULL GROUP BY product_name ORDER BY COUNT(*) DESC;
SELECT sales_channel, COUNT(*) FROM clean_sales WHERE unit_price IS NULL GROUP BY sales_channel ORDER BY COUNT(*) DESC;
SELECT sales_rep, COUNT(*) FROM clean_sales WHERE unit_price IS NULL GROUP BY sales_rep ORDER BY COUNT(*) DESC;
SELECT MIN(order_date), MAX(order_date) FROM clean_sales WHERE unit_price IS NULL;
-- Conclusion: no product/rep clustering, mild channel skew (Wholesale), spread across
-- the full year — treated as a low-level, evenly distributed recording gap, not a
-- systemic bug tied to one source. Flagged rather than deleted.

ALTER TABLE clean_sales ADD COLUMN data_quality_flag TEXT;

UPDATE clean_sales
SET data_quality_flag = 'missing_pricing_data'
WHERE unit_price IS NULL;

SELECT data_quality_flag, COUNT(*) FROM clean_sales GROUP BY data_quality_flag;
-- expect: NULL/blank 4753, missing_pricing_data 247

-- 7b. region vs. address_city — confirm relationship (or lack of one)
SELECT DISTINCT address_city, region FROM clean_sales ORDER BY address_city, region;
-- Cross-tab in Power BI (address_city x region, count of order_id) showed every city's
-- orders spread nearly evenly across all four regions — no reliable mapping.
-- Decision: exclude `region` from geographic analysis; rely on address_city instead.
-- Column retained in the table (not dropped) but not used in reporting.

-- 7c. city_unreliable — dropped after address_city was established as the trustworthy field
-- (original `city` staging column was never carried into clean_sales at all — see step 5)

-- ------------------------------------------------------------
-- 8. FINAL TABLE
-- Written from Python/pandas after the above flagging.
-- These SELECTs verify what Python wrote back via to_sql().
-- ------------------------------------------------------------
SELECT COUNT(*) FROM final_sales;  -- expect 5000
SELECT data_quality_flag, COUNT(*) FROM final_sales GROUP BY data_quality_flag;
