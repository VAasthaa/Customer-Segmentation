USE retail_analytics;
DROP TABLE IF EXISTS retail;
CREATE TABLE retail (
  invoice       VARCHAR(20),
  stock_code    VARCHAR(20),
  description   VARCHAR(255),
  quantity      VARCHAR(20),
  invoice_date  VARCHAR(30),
  price         VARCHAR(20),
  customer_id   VARCHAR(20),
  country       VARCHAR(60)
);

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'online_retail.csv'
INTO TABLE retail
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 3.1 Did everything load? Expect 1,067,371 rows.
SELECT COUNT(*) AS raw_rows FROM retail;

-- 3.2 Look at a few rows: check the date format and the customer_id format
SELECT * FROM retail LIMIT 10;

-- 3.3 Data problems we need to handle
SELECT
  SUM(TRIM(customer_id) = '' OR customer_id IS NULL) AS missing_customer,   -- about 243k
  SUM(invoice LIKE 'C%')                             AS cancelled_rows,     -- about 19.5k
  SUM(CAST(quantity AS SIGNED) <= 0)                 AS zero_or_neg_qty,
  SUM(CAST(price AS DECIMAL(12,3)) <= 0)             AS zero_or_neg_price,
  SUM(stock_code NOT REGEXP '^[0-9]{5}')             AS non_product_codes
FROM retail;

-- 3.4 What are the non-product stock codes? (postage, fees, manual adjustments)
SELECT stock_code, MIN(description) AS example_description, COUNT(*) AS rows_
FROM retail
WHERE stock_code NOT REGEXP '^[0-9]{5}'
GROUP BY stock_code
ORDER BY rows_ DESC
LIMIT 20;

DROP TABLE IF EXISTS transactions;
CREATE TABLE transactions AS
SELECT DISTINCT
  TRIM(invoice)                                            AS invoice,
  TRIM(stock_code)                                         AS stock_code,
  TRIM(description)                                        AS description,
  CAST(quantity AS SIGNED)                                 AS quantity,
  CASE
    WHEN invoice_date LIKE '%/%' THEN STR_TO_DATE(invoice_date, '%m/%d/%Y %H:%i')
    ELSE STR_TO_DATE(invoice_date, '%Y-%m-%d %H:%i:%s')
  END                                                      AS invoice_date,
  CAST(price AS DECIMAL(12,3))                             AS price,
  CASE
    WHEN TRIM(customer_id) = '' THEN NULL
    ELSE CAST(CAST(TRIM(customer_id) AS DECIMAL(12,1)) AS UNSIGNED)
  END                                                      AS customer_id,
  TRIM(TRAILING '\r' FROM TRIM(country))                   AS country,
  (invoice LIKE 'C%')                                      AS is_cancelled
FROM retail;

SELECT COUNT(*)                  AS rows_after_dedup,
       MIN(invoice_date)         AS first_date,
       MAX(invoice_date)         AS last_date,
       SUM(invoice_date IS NULL) AS null_dates,
       COUNT(DISTINCT customer_id) AS customers
FROM transactions;

DROP TABLE IF EXISTS sales;
CREATE TABLE sales AS
SELECT invoice, stock_code, description, quantity, invoice_date, price,
       customer_id, country,
       ROUND(quantity * price, 2) AS revenue
FROM transactions
WHERE is_cancelled = 0
  AND quantity > 0
  AND price > 0
  AND customer_id IS NOT NULL
  AND stock_code REGEXP '^[0-9]{5}';
  
CREATE INDEX idx_sales_customer ON sales (customer_id);
CREATE INDEX idx_sales_date     ON sales (invoice_date);
CREATE INDEX idx_sales_invoice  ON sales (invoice);


-- 6.1 Size of the clean data 
SELECT COUNT(*)                    AS clean_rows,
       COUNT(DISTINCT customer_id) AS customers,
       COUNT(DISTINCT invoice)     AS orders,
       COUNT(DISTINCT stock_code)  AS products,
       COUNT(DISTINCT country)     AS countries,
       ROUND(SUM(revenue), 0)      AS total_revenue_gbp
FROM sales;

-- 6.2 Where did the rows go? 
SELECT 'Raw rows'                               AS step, COUNT(*) AS rows_ FROM retail
UNION ALL
SELECT 'After removing duplicates',                 COUNT(*) FROM transactions
UNION ALL
SELECT 'Excluding cancellations',                   COUNT(*) FROM transactions WHERE is_cancelled = 0
UNION ALL
SELECT 'With a known customer',                     COUNT(*) FROM transactions WHERE is_cancelled = 0 AND customer_id IS NOT NULL
UNION ALL
SELECT 'Final clean sales',                         COUNT(*) FROM sales;

-- 6.3 Nothing invalid left 
SELECT SUM(quantity <= 0)          AS bad_qty,
       SUM(price <= 0)             AS bad_price,
       SUM(customer_id IS NULL)    AS null_customer,
       SUM(invoice_date IS NULL)   AS null_date
FROM sales;