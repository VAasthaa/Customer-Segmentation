-- =====================================================================
-- CUSTOMER SEGMENTATION PROJECT - Part 2: Business questions
-- Uses the clean `sales` table (and `transactions` for cancellations).
-- Sections A-G follow the business problem:
--   A. How is the business doing?        E. RFM segmentation (core)
--   B. What do cancellations cost?       F. Who to target, and what it's worth
--   C. How concentrated is revenue?      G. Do customers come back? (cohorts)
--   D. New vs returning customers
-- Tables created for Power BI: customer_rfm, cohort_retention
-- Note: the data ends on 2011-12-09, so December 2011 is a partial month.
-- =====================================================================
USE retail_analytics;


-- =====================================================================
-- A. HOW IS THE BUSINESS DOING?
-- =====================================================================

-- A1. Headline KPIs
SELECT ROUND(SUM(revenue), 0)                              AS total_revenue_gbp,
       COUNT(DISTINCT invoice)                             AS total_orders,
       COUNT(DISTINCT customer_id)                         AS total_customers,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)    AS avg_order_value,
       ROUND(COUNT(DISTINCT invoice) / COUNT(DISTINCT customer_id), 1) AS orders_per_customer
FROM sales;

-- A2. Monthly revenue with month-over-month growth (LAG window function)
WITH monthly AS (
  SELECT DATE_FORMAT(invoice_date, '%Y-%m') AS month,
         ROUND(SUM(revenue), 0)             AS revenue,
         COUNT(DISTINCT invoice)            AS orders,
         COUNT(DISTINCT customer_id)        AS active_customers
  FROM sales
  GROUP BY month
)
SELECT month, revenue, orders, active_customers,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- A3. Year-over-year: compare the two full Dec-Nov years
SELECT CASE WHEN invoice_date < '2010-12-01' THEN 'Dec 2009 - Nov 2010'
            ELSE 'Dec 2010 - Nov 2011' END            AS period,
       ROUND(SUM(revenue), 0)                         AS revenue,
       COUNT(DISTINCT customer_id)                    AS customers,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2) AS avg_order_value
FROM sales
WHERE invoice_date < '2011-12-01'
GROUP BY period;

-- A4. Top 10 countries by revenue, with share of total
SELECT country,
       ROUND(SUM(revenue), 0)                                    AS revenue,
       COUNT(DISTINCT customer_id)                               AS customers,
       ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS revenue_share_pct
FROM sales
GROUP BY country
ORDER BY revenue DESC
LIMIT 10;

-- A5. Top 10 products by revenue
SELECT stock_code,
       MAX(description)            AS description,
       SUM(quantity)               AS units_sold,
       ROUND(SUM(revenue), 0)      AS revenue,
       COUNT(DISTINCT customer_id) AS customers_who_bought
FROM sales
GROUP BY stock_code
ORDER BY revenue DESC
LIMIT 10;

-- A6. When do customers order? Day of week and hour
SELECT DAYNAME(invoice_date) AS day_of_week,
       COUNT(DISTINCT invoice) AS orders,
       ROUND(SUM(revenue), 0)  AS revenue
FROM sales
GROUP BY day_of_week, DAYOFWEEK(invoice_date)
ORDER BY DAYOFWEEK(invoice_date);

SELECT HOUR(invoice_date) AS hour_of_day,
       COUNT(DISTINCT invoice) AS orders
FROM sales
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- =====================================================================
-- B. WHAT DO CANCELLATIONS COST?
-- =====================================================================

-- B1. Cancellation rate and lost revenue (from the full transactions table)
SELECT COUNT(DISTINCT invoice)                                        AS all_invoices,
       COUNT(DISTINCT CASE WHEN is_cancelled = 1 THEN invoice END)    AS cancelled_invoices,
       ROUND(100 * COUNT(DISTINCT CASE WHEN is_cancelled = 1 THEN invoice END)
                 / COUNT(DISTINCT invoice), 2)                        AS cancellation_rate_pct,
       ROUND(SUM(CASE WHEN is_cancelled = 1 THEN ABS(quantity) * price END), 0) AS cancelled_value_gbp
FROM transactions;

-- B2. Most-cancelled products
SELECT stock_code, MAX(description) AS description,
       COUNT(*)                            AS cancellation_lines,
       ROUND(SUM(ABS(quantity) * price), 0) AS cancelled_value_gbp
FROM transactions
WHERE is_cancelled = 1 AND stock_code REGEXP '^[0-9]{5}'
GROUP BY stock_code
ORDER BY cancelled_value_gbp DESC
LIMIT 10;


-- =====================================================================
-- C. HOW CONCENTRATED IS REVENUE? (Pareto / 80-20 check)
-- =====================================================================

-- C1. Revenue share of the top 20% of customers
WITH cust AS (
  SELECT customer_id, SUM(revenue) AS rev
  FROM sales GROUP BY customer_id
),
ranked AS (
  SELECT rev,
         ROW_NUMBER() OVER (ORDER BY rev DESC) AS rn,
         COUNT(*)     OVER ()                  AS n,
         SUM(rev)     OVER ()                  AS total
  FROM cust
)
SELECT ROUND(100 * SUM(CASE WHEN rn <= 0.2 * n THEN rev END) / MAX(total), 1) AS top20_revenue_share_pct,
       ROUND(100 * SUM(CASE WHEN rn <= 0.01 * n THEN rev END) / MAX(total), 1) AS top1_revenue_share_pct
FROM ranked;

-- C2. Revenue by customer decile (decile 1 = biggest spenders). Good for a bar chart.
WITH cust AS (
  SELECT customer_id, SUM(revenue) AS rev
  FROM sales GROUP BY customer_id
)
SELECT decile,
       COUNT(*)                                             AS customers,
       ROUND(SUM(rev), 0)                                   AS revenue,
       ROUND(100 * SUM(rev) / SUM(SUM(rev)) OVER (), 1)     AS revenue_share_pct
FROM (SELECT rev, NTILE(10) OVER (ORDER BY rev DESC) AS decile FROM cust) d
GROUP BY decile
ORDER BY decile;


-- =====================================================================
-- D. NEW vs RETURNING CUSTOMERS EACH MONTH
-- =====================================================================
WITH first_purchase AS (
  SELECT customer_id, DATE_FORMAT(MIN(invoice_date), '%Y-%m') AS first_month
  FROM sales GROUP BY customer_id
),
monthly AS (
  SELECT DISTINCT customer_id, DATE_FORMAT(invoice_date, '%Y-%m') AS month
  FROM sales
)
SELECT m.month,
       SUM(m.month = f.first_month)  AS new_customers,
       SUM(m.month > f.first_month)  AS returning_customers,
       ROUND(100 * SUM(m.month > f.first_month) / COUNT(*), 1) AS returning_pct
FROM monthly m
JOIN first_purchase f ON f.customer_id = m.customer_id
GROUP BY m.month
ORDER BY m.month;
-- Dec 2009 shows everyone as "new" because that's where the data starts.


-- =====================================================================
-- E. RFM SEGMENTATION (the core of the project)
-- =====================================================================
-- Recency   = days since last order, measured from the day after the
--             last date in the data (2011-12-10), as if analysing "today"
-- Frequency = number of distinct orders
-- Monetary  = total spend
-- Each is scored 1-5 with NTILE(5); 5 = best.
-- Recency is ordered DESC, so the most recent buyers get 5.

DROP TABLE IF EXISTS customer_rfm;
CREATE TABLE customer_rfm
WITH base AS (
  SELECT customer_id,
         MAX(country)                                         AS country,
         MIN(invoice_date)                                    AS first_order,
         MAX(invoice_date)                                    AS last_order,
         DATEDIFF((SELECT DATE(MAX(invoice_date)) + INTERVAL 1 DAY FROM sales),
                  MAX(invoice_date))                          AS recency_days,
         COUNT(DISTINCT invoice)                              AS frequency,
         ROUND(SUM(revenue), 2)                               AS monetary
  FROM sales
  GROUP BY customer_id
),
scored AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
         NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
         NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
  FROM base
)
SELECT *,
       CONCAT(r_score, f_score, m_score)    AS rfm_code,
       ROUND((f_score + m_score) / 2)       AS fm_score,
       CASE
         WHEN r_score >= 4 AND ROUND((f_score + m_score) / 2) >= 4 THEN 'Champions'
         WHEN r_score >= 3 AND ROUND((f_score + m_score) / 2) >= 3 THEN 'Loyal'
         WHEN r_score >= 4                                          THEN 'New / Promising'
         WHEN r_score  = 3                                          THEN 'Need Attention'
         WHEN ROUND((f_score + m_score) / 2) >= 3                   THEN 'At Risk'
         ELSE 'Lost'
       END AS segment
FROM scored;
-- How the segments read:
--   Champions       bought recently, buy often, spend a lot   -> reward, early access
--   Loyal           solid on all three                         -> upsell, loyalty perks
--   New / Promising bought recently but not much yet           -> onboarding, 2nd-order offer
--   Need Attention  middling recency, low value                -> reminders
--   At Risk         USED to buy often and spend a lot, gone quiet -> win-back now
--   Lost            long gone, low value                       -> low-cost campaigns only

-- E1. Check: one row per customer, scores spread evenly
SELECT COUNT(*) AS customers,
       MIN(recency_days) AS min_recency, MAX(recency_days) AS max_recency,
       MIN(frequency) AS min_freq, MAX(frequency) AS max_freq
FROM customer_rfm;

-- E2. Segment summary: the main result table of the project
SELECT segment,
       COUNT(*)                                                   AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_customers,
       ROUND(SUM(monetary), 0)                                    AS revenue,
       ROUND(100 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(recency_days), 0)                                AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                   AS avg_orders,
       ROUND(AVG(monetary), 0)                                    AS avg_spend
FROM customer_rfm
GROUP BY segment
ORDER BY revenue DESC;


-- =====================================================================
-- F. WHO TO TARGET, AND WHAT IT'S WORTH
-- =====================================================================

-- F1. Revenue at stake: At Risk customers' spend in their last 12 months of activity
--     (this is the money a win-back campaign is trying to protect)
SELECT COUNT(DISTINCT r.customer_id)  AS at_risk_customers,
       ROUND(SUM(s.revenue), 0)       AS their_last_12m_revenue_gbp
FROM customer_rfm r
JOIN sales s
  ON s.customer_id = r.customer_id
 AND s.invoice_date > r.last_order - INTERVAL 12 MONTH
WHERE r.segment = 'At Risk';

-- F2. Top 20 At Risk customers by lifetime spend: the win-back priority list
SELECT customer_id, country, recency_days, frequency, monetary, last_order
FROM customer_rfm
WHERE segment = 'At Risk'
ORDER BY monetary DESC
LIMIT 20;

-- F3. Segments by country (top 5 countries): does the mix differ outside the UK?
SELECT country, segment, COUNT(*) AS customers
FROM customer_rfm
WHERE country IN (SELECT country FROM (
        SELECT country FROM customer_rfm GROUP BY country
        ORDER BY COUNT(*) DESC LIMIT 5) t)
GROUP BY country, segment
ORDER BY country, customers DESC;


-- =====================================================================
-- G. DO CUSTOMERS COME BACK? (monthly cohort retention)
-- =====================================================================
-- Cohort = the month of a customer's first order.
-- For each cohort: what % of its customers bought again 1, 2, 3... months later.

DROP TABLE IF EXISTS cohort_retention;
CREATE TABLE cohort_retention
WITH first_purchase AS (
  SELECT customer_id,
         CAST(DATE_FORMAT(MIN(invoice_date), '%Y-%m-01') AS DATE) AS cohort_month
  FROM sales GROUP BY customer_id
),
activity AS (
  SELECT DISTINCT customer_id,
         CAST(DATE_FORMAT(invoice_date, '%Y-%m-01') AS DATE) AS activity_month
  FROM sales
),
joined AS (
  SELECT f.cohort_month,
         TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month) AS months_since_first,
         a.customer_id
  FROM first_purchase f
  JOIN activity a ON a.customer_id = f.customer_id
),
counts AS (
  SELECT cohort_month, months_since_first, COUNT(*) AS active_customers
  FROM joined
  GROUP BY cohort_month, months_since_first
)
SELECT c.cohort_month,
       c.months_since_first,
       c.active_customers,
       s.active_customers                                   AS cohort_size,
       ROUND(100 * c.active_customers / s.active_customers, 1) AS retention_pct
FROM counts c
JOIN counts s
  ON s.cohort_month = c.cohort_month AND s.months_since_first = 0;

-- G1. Retention grid for 2010 cohorts, first 6 months (pivot with CASE)
SELECT cohort_month,
       MAX(CASE WHEN months_since_first = 0 THEN cohort_size END)   AS cohort_size,
       MAX(CASE WHEN months_since_first = 1 THEN retention_pct END) AS m1,
       MAX(CASE WHEN months_since_first = 2 THEN retention_pct END) AS m2,
       MAX(CASE WHEN months_since_first = 3 THEN retention_pct END) AS m3,
       MAX(CASE WHEN months_since_first = 6 THEN retention_pct END) AS m6,
       MAX(CASE WHEN months_since_first = 12 THEN retention_pct END) AS m12
FROM cohort_retention
WHERE cohort_month BETWEEN '2010-01-01' AND '2010-12-01'
GROUP BY cohort_month
ORDER BY cohort_month;

-- G2. Average month-1 retention across cohorts: one number for the resume
SELECT ROUND(AVG(retention_pct), 1) AS avg_month1_retention_pct
FROM cohort_retention
WHERE months_since_first = 1
  AND cohort_month BETWEEN '2010-01-01' AND '2011-10-01';
-- Dec 2009 is excluded because that cohort includes every customer who
-- existed before the data starts, not only genuinely new ones.
