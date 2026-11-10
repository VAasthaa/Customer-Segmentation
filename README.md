# Customer Segmentation & Retention (MySQL + Power BI)

RFM segmentation and cohort retention analysis of a UK online retailer, to find **which customers drive revenue, who is about to churn, and how many customers come back**.

![Overview](images/cs_overview.png)
![RFM segments](images/cs_rfm_segments.png)
![Retention](images/cs_retention.png)

## Business problem

An online gift retailer sells to thousands of customers, mostly wholesalers. Marketing treats every customer the same, so money is spent on people who will never return while the best customers get no special attention. The business wants to know:

- How is the business doing, and where does revenue come from?
- Which customers are the most valuable, and which are slipping away?
- Who should be targeted for retention, and how much revenue is at stake?
- Do new customers come back after their first order?

## Dataset

- **Source:** [Online Retail II (UCI), Kaggle](https://www.kaggle.com/datasets/mashlyn/online-retail-ii-uci)
- **Period:** 1 Dec 2009 – 9 Dec 2011 (December 2011 is a partial month)
- **Size:** 1,067,371 transaction lines, one row per product per invoice
- **Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country

## Approach

### 1. Data cleaning: [`sql/01_data_cleaning.sql`](sql/01_data_cleaning.sql)

| Step | Rows |
|---|---|
| Raw data | 1,067,371 |
| After removing exact duplicates | 1,033,036 |
| Excluding cancelled invoices (start with "C") | 1,013,932 |
| With a known customer ID | 779,495 |
| **Final clean sales** (quantity > 0, price > 0, real products only) | **776,577** |

- Loaded the CSV into a raw text table with `LOAD DATA`
- Converted types, handled two date formats, and turned customer IDs like `13085.0` into whole numbers
- Removed non-product codes (postage, fees, manual adjustments) using `REGEXP '^[0-9]{5}'`
- Kept cancellations in a separate `transactions` table so their cost could be analysed
- Added indexes for faster queries

### 2. Business questions: [`sql/02_business_questions.sql`](sql/02_business_questions.sql)

| Section | Question |
|---|---|
| A | Headline KPIs, monthly revenue with month-over-month growth (`LAG`), year-over-year, top countries and products |
| B | Cancellation rate and the value of cancelled orders |
| C | Revenue concentration: share of the top 20% and top 1% of customers, and customer deciles (`NTILE`) |
| D | New vs returning customers each month |
| E | **RFM segmentation:** recency, frequency and monetary scored 1–5 with `NTILE(5)`, then mapped to 6 segments |
| F | At-risk customers: revenue at stake and a top 20 win-back list |
| G | **Monthly cohort retention:** % of each month's new customers who bought again 1–12 months later |

**SQL used:** CTEs, window functions (`LAG`, `NTILE`, `ROW_NUMBER`, `SUM() OVER()`), `CASE`, `REGEXP`, `DATEDIFF`, `TIMESTAMPDIFF`, joins, and summary tables created for Power BI (`customer_rfm`, `cohort_retention`)

### 3. Dashboard (Power BI)
Three pages: **Overview**, **RFM segments** (with a country slicer) and **Retention**.

## Key findings

| KPI | Value |
|---|---|
| Total revenue | £17.07M |
| Customers | 5,852 |
| Orders | 36,594 |
| Average order value | £466.43 |

- **Seasonality:** revenue peaks every November ahead of Christmas (£1.16M in Nov 2010, £1.14M in Nov 2011).
- **Geography:** the UK brings in 83.7% of revenue. EIRE (3.4%) and the Netherlands (3.2%) are next.
- **Concentration:** the top 20% of customers bring in **77.2% of revenue**, and the top 1% alone bring in 31.9%.
- **Cancellations:** 15.5% of invoices were cancelled, worth about £1.46M.
- **RFM segments:**

| Segment | Customers | % of customers | % of revenue | Action |
|---|---|---|---|---|
| Champions | 1,595 | 27.3% | **71.6%** | Reward, early access |
| Loyal | 1,247 | 21.3% | 14.3% | Upsell, loyalty perks |
| At Risk | 975 | 16.7% | 10.7% | **Win back now** |
| Lost | 1,367 | 23.4% | 2.2% | Low-cost campaigns only |
| New / Promising | 378 | 6.5% | 0.6% | Onboarding, second-order offer |
| Need Attention | 290 | 5.0% | 0.5% | Reminders |

- **At risk:** 975 customers who used to buy often have gone quiet. Together they have spent **£1.83M**, which is the revenue a win-back campaign would try to protect.
- **Retention:** on average only **20.7%** of new customers buy again in the month after their first order, and retention falls to around 13–14% by months 9–11.

## Tools

MySQL 8 · MySQL Workbench · Power BI

## Repository structure

```
├── sql/
│   ├── 01_data_cleaning.sql
│   └── 02_business_questions.sql
├── images/
│   ├── cs_overview.png
│   ├── cs_rfm_segments.png
│   └── cs_retention.png
└── README.md
```

---
**Author:** Aastha Verma · [LinkedIn](https://www.linkedin.com/in/verma-aastha)
