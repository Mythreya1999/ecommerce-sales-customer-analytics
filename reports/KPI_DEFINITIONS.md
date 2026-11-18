# KPI Definitions

Every metric in this project, its formula, and the definitional decision behind it.
**If a number appears in a slide, a dashboard, or this repo, it is defined here.**

The single most important line in this document is **§1: which orders count**. Three defensible
answers differ by ₹303 M, and every downstream metric inherits the choice.

---

## 0. Scope

| Item | Value |
|---|---|
| Dataset period | 2023-01-01 → 2025-12-31 |
| Cutoff date for recency / churn | 2025-12-31 |
| Data source | `db/ecommerce.db` (built from `data/source/*.csv`) |
| Grain of the fact view | one order line item (254,331 rows) |
| Currency | INR (₹), unadjusted |

---

## 1. Revenue base — the governing decision

| Definition | Formula | Value | Use |
|---|---|---:|---|
| **A. All orders** | `SUM(item_revenue)` over every order | ₹2,449,898,974 | ❌ never — includes orders that never happened |
| **B. Order book** | same, `WHERE order_status <> 'Failed'` | ₹2,381,509,750 | Order-book / pipeline reporting only |
| **C. Realised** ✅ | same, `WHERE order_status IN ('Delivered','Returned')` | **₹2,146,672,725** | **Every KPI in this project** |

The A → C gap is **₹303.2 M** of cancelled, failed and still-processing demand. Reporting A as
"revenue" overstates the business by **14.1%**.

**Implementation:** `v_sales.is_realised = 1`. No KPI may bypass this flag.

---

## 2. Financial KPIs

| KPI | Formula | Value |
|---|---|---:|
| **Total Sales** | `SUM(line_revenue) WHERE is_realised = 1` | ₹2,146,672,724.50 |
| **Total Cost** | `SUM(line_cost) WHERE is_realised = 1` | ₹1,974,324,163.38 |
| **Gross Profit** | `SUM(line_profit) WHERE is_realised = 1` | ₹172,348,561.12 |
| **Gross Margin %** | `Gross Profit / Total Sales` | 8.03% |
| **Lost Revenue** | `SUM(line_revenue) WHERE is_lost_sale = 1` | ₹261,358,234 |
| **Lost Revenue % of Demand** | `Lost Revenue / (Lost Revenue + Total Sales)` | 10.7% |
| **Return Rate %** | `COUNT(is_returned_item = 1) / COUNT(*)` on realised lines | 5.29% |

### Why item level, not `final_amount`

`orders.final_amount` = merchandise **+ shipping + tax**. Using it as the revenue base mixes
cost-recovery items into a margin calculation, and inflates the denominator:

| Base | Revenue | Gross margin |
|---|---:|---:|
| **Item level (used)** | ₹2,146,672,725 | **8.03%** |
| Order `final_amount` | ₹2,254,178,763 | 7.65% |

A 0.38 pp difference — small, but it compounds across every product, category and region
breakdown. Shipping is not revenue for a marketplace and tax is never revenue, so item level is the
honest base. `final_amount` is used only for the order-book reconciliation in §1.

### Both `orders.discount_percentage` and `line_revenue`

`line_revenue = quantity × unit_price × (1 − item_discount%)`. The **order-level**
`discount_percentage` is **not** applied to `final_amount` — the dataset's `final_amount` =
`subtotal + tax + shipping` with a **max diff of 0.00** against that formula on all 100,000 orders.
Applying the order-level discount on top of `subtotal` **double-counts** it.

---

## 3. Volume KPIs

| KPI | Formula | Value |
|---|---|---:|
| **Total Orders** | `DISTINCTCOUNT(order_id) WHERE is_realised = 1` | 87,360 |
| **Total Customers** | `DISTINCTCOUNT(customer_id) WHERE is_realised = 1` | 22,208 |
| **Units Sold** | `SUM(quantity) WHERE is_realised = 1` | 512,014 |
| **Average Order Value** | `Total Sales / Total Orders` | ₹24,572.72 |
| **Revenue per Customer** | `Total Sales / Total Customers` | ₹96,662.14 |
| **Units per Order** | `Units Sold / Total Orders` | 5.86 |

**Denominator discipline:** AOV divides by **orders**. Dividing by rows gives average *line* value
(₹9,659) — a different, much smaller number that is often mislabelled as AOV.

Note the three different customer counts, and which one a KPI should use:

| Count | Value | Meaning |
|---|---:|---|
| `dim_customers` rows | 25,000 | every registered customer |
| `customer_id` in the fact table | 22,820 | ever placed an order (any status) |
| **`DISTINCTCOUNT` on realised sales** | **22,208** | **actually bought** |

2,792 of the 25,000 registered customers have **no realised order**: 2,300 carry the dataset's
`Never Purchased` label, and 492 shop only in cancelled/failed/processing orders. Note that 201 of
those 492 are labelled `Active` — the dataset's status rule uses `last_order_date` across *all*
orders, not just realised ones. That is a definitional quirk to be aware of, not an error.

"Customers" in this project always means **buying customers = 22,208**.

---

## 4. Customer KPIs

| KPI | Formula | Value |
|---|---|---:|
| **Repeat Rate %** | `repeat customers / buying customers` | 80.19% |
| **One-time customers** | `COUNT(customers with exactly 1 realised order)` | 4,399 |
| **Revenue from repeat** | share of Total Sales from repeat customers | 95.6% |
| **Customers for 50% of revenue** | cumulative Pareto rank | 3,212 (14.5%) |
| **Customers for 80% of revenue** | cumulative Pareto rank | 7,839 (35.3%) |
| **Recency Days** | `2025-12-31 − MAX(order_date)` | per customer |
| **Month-12 cohort activity** | cohort active in month 12 / cohort size | 6.8% |

**Churn / status** (`customers.customer_status`) is a **dataset-provided derived label**:
`Active` ≤ 90 days, `At Risk` ≤ 180 days, `Churned` > 180 days before 2025-12-31. It is reused as-is
so the project reconciles with the source — it is **not** independently recomputed.

**RFM** uses quintile scoring (1–5) on `recency_days`, `order count`, and `revenue`, averaged into
`RFM score`. Segments are rule-based (see `sql/03` Q2 or `dax_measures.dax → RFM Segment`).

---

## 5. Product KPIs

| KPI | Formula | Value |
|---|---|---:|
| **Product Revenue Rank** | `RANKX` over product revenue, realised only | — |
| **Category Margin %** | `SUM(line_profit) / SUM(line_revenue)` per category | 0.67% – 33.17% |
| **Product Cumulative Share %** | running revenue share in descending rank order | Pareto curve |
| **Discount Band** | `line`-level `item_discount_pct` bucketed | 5 bands |
| **Return Rate (category)** | `COUNT(is_returned_item) / COUNT(*)` | 3.1% – 9.4% |

**Concentration:** 13 of 550 products (2.4%) = 50% of revenue; 53 (9.6%) = 80%; 108 (19.6%) = 90%.

---

## 6. Operational KPIs

| KPI | Formula | Value |
|---|---|---:|
| **Delayed Delivery %** | `AVG(delayed_flag)` on realised lines with a shipment | 42.8% |
| **Average Delivery Days** | `AVG(delivery_days)` | 4.10 |

`delayed_flag = 1` when `actual_delivery_date > expected_delivery_date` (dataset-provided).
2,321 shipments are `Cancelled in Transit` and have **no** actual delivery date — these are excluded
from the denominator, not counted as on-time.

---

## 7. Time KPIs

| KPI | Formula | Value |
|---|---|---:|
| **YoY Growth** | `(Sales_2025 − Sales_2024) / Sales_2024` | +67.8% |
| **Q4 Share (pooled)** | Q4 sales / total sales across 3 years | 36.9% |
| **Q4-2025 Share** | Q4-2025 / total sales | 20.1% |
| **Seasonality Index** | `revenue per trading day in month ÷ average` | Jan 65 → Dec 159 |
| **Peak/Trough ratio** | Dec vs Jan revenue per trading day | 2.46× |

---

## 8. Things deliberately NOT measured

| Not measured | Why |
|---|---|
| **CAC** | No per-customer marketing spend. `campaign_cost` is campaign-level only. |
| **True CLV** | Requires retention curve × margin × discount rate over a future horizon; only 36 months of history and a synthetic churn process. |
| **Price elasticity** | No price experiment in the data. The discount recommendation is a **hypothesis to test**, not a measured effect. |
| **Net revenue / contribution margin** | No fulfilment cost per order, no returns-processing cost, no payment gateway fee per gateway (only `transaction_fee`). |
| **Session / funnel conversion** | No clickstream. `impressions` and `clicks` in `marketing_campaigns` are synthetic placeholders derived backwards from CTR assumptions. |

Stating these explicitly is part of the analysis: a KPI that cannot be computed should be named as a
gap, not approximated silently.
