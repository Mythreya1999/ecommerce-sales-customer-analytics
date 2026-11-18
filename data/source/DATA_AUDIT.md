# Data Audit — Indian E-Commerce Customer & Order Intelligence Dataset

**Audited:** 2026-11-15 · **Verdict:** ✅ **Usable and unusually well-built.** All structural integrity
checks pass. The issues found are *definitional traps*, not corrupt data — they will silently produce
wrong KPIs if you don't know about them.

---

## 1. Inventory

| Table | Rows | Cols | Grain | Availability |
|---|---:|---:|---|---|
| customers | 25,000 | 18 | 1 / customer | ✅ |
| products | 550 | 14 | 1 / product | ✅ |
| orders | 100,000 | 16 | 1 / order | ✅ |
| order_items | 254,331 | 9 | 1 / line item | ✅ |
| payments | 100,000 | 8 | 1 / order | ✅ |
| shipments | 89,681 | 11 | 1 / shipped order | ✅ |
| returns | 12,075 | 8 | 1 / returned item | ✅ |
| customer_reviews | 77,530 | 8 | 1 / review | ✅ |
| marketing_campaigns | 151 | 14 | 1 / campaign | ✅ |

Total ≈ 559,000 rows, 106 documented columns. Period 2023-01-01 → 2025-12-31.
Note: `quick_eda.py` is referenced in the README but **is not present** in the folder.

## 2. Integrity checks — all PASS

| Check | Result |
|---|---|
| Primary keys unique (8 tables) | 0 duplicates |
| Foreign keys (9 relationships) | 0 orphans |
| Full-row duplicates | 0 in every table |
| `orders.subtotal` = `SUM(item_revenue)` | 0 mismatches, max diff **0.00** |
| `final_amount` = subtotal + tax + shipping | 0 mismatches, max diff **0.00** |
| `item_revenue` = qty × unit_price × (1−disc) | 0 mismatches |
| `profit` = item_revenue − item_cost | exact |
| `unit_price` = `products.price` | exact (0% deviation) |
| Refund ≤ paid / ≤ item_revenue | 0 violations |
| Date ranges | all inside 2023-01-01 → 2025-12-31 |
| Duplicate business keys (customer+date+amount) | 0 |

**This is much cleaner than a typical real-world dataset.** No cleaning is required before analysis.

## 3. ⚠️ Definitional traps — read before writing any KPI

### 3.1 Two legitimate revenue definitions, ₹71.8 Cr apart
| Definition | Value |
|---|---:|
| GMV — all orders | ₹2,572,592,369 |
| GMV — excluding `Failed` | ₹2,500,777,756 |
| Realised — `Delivered` + `Returned` only | ₹2,254,178,763 |

`customers.total_spend` and `customers.total_orders` **exclude `Failed` orders** — verified with zero
exceptions. So `SUM(customers.total_spend)` = ₹2,500,777,756, *not* the full order book. Pick one
definition per report and state it.

### 3.2 `orders.discount_percentage` is NOT applied to `final_amount`
`subtotal` is already net of the **item-level** discount. The order-level `discount_percentage` is a
separate, coarser promo attribute (0/5/10/…/30) that has **no monetary effect**. 20,930 orders carry
item-level discounts while `orders.discount_percentage = 0`.
➡️ Computing `subtotal × (1 − orders.discount_percentage/100)` **double-counts the discount**.

### 3.3 Two refund sources disagree by 2.5×
| Source | Total refunds |
|---|---:|
| `payments.refund_amount` | ₹268,740,812 |
| `returns.refund_amount` | ₹105,898,382 |

`payments` includes refunds on cancelled/failed orders; `returns` is item-level and only covers
initiated returns. Never mix the two in one metric.

### 3.4 `payments.amount_paid` is 0 for 7,173 orders
Exactly the `Failed` (5,068) + `Not Charged` (1,876) + `Pending` (229) rows. Correct behaviour, but
revenue built from `amount_paid` silently drops them. There is **no `discount_amount` column** —
order value must be reconstructed as `subtotal + tax_amount + shipping_fee`.

### 3.5 `returns` is not fully consistent with `order_status`
- 2,458 return rows sit on orders still marked `Delivered` (partial returns — status never updated).
- **402 return rows sit on `Cancelled` / `Failed` / `Processing` orders** — logically impossible,
  since those never shipped. ~3.3% of return rows. Filter these out of return-rate analysis.

### 3.6 `marketing_campaigns.roi` is a **multiplier, not a percentage**
`roi = round((revenue − cost) / cost, 3)` — verified on all 151 rows. Mean 2.41 means **241% return**,
not 2.4%. Also note: `orders.campaign_id` is populated on only 17,179 / 100,000 orders (17%), so
attributed revenue (₹436M) covers a fraction of GMV by design.

### 3.7 `order_items` has 2,019 duplicate `(order_id, product_id)` pairs
Legitimate separate line items — but any join on `(order_id, product_id)` must aggregate first, or
you will fan out rows.

### 3.8 "Never Purchased" ≠ zero orders
2,300 customers carry that label; **120 of them have orders — all `Failed`**. Correct under the
non-Failed definition, confusing if you validate naively.

## 4. Nulls (all explainable)

| Column | Nulls | Meaning |
|---|---:|---|
| `customers.age` | 250 (1.0%) | genuine MCAR gap |
| `customers.preferred_device` | 125 (0.5%) | genuine MCAR gap |
| `customers.last_order_date` | 2,300 | exactly the never-purchased cohort — **not** missing data |
| `products.rating_average` | 4 (0.7%) | MCAR gap |
| `orders.coupon_code` | 33,711 (34%) | no coupon used |
| `orders.campaign_id` | 82,821 (83%) | no campaign attribution |
| `shipments.actual_delivery_date` | 2,321 | exactly the "Cancelled in Transit" rows — consistent |
| `customer_reviews.review_sentiment` | 233 (0.3%) | MCAR gap |

## 5. Business shape (sanity)

- Order status: Delivered 80,679 · Cancelled 8,073 · Returned 6,681 · Failed 2,880 · Processing 1,687
- Customer status: Churned 13,365 · Active 7,234 · Never Purchased 2,300 · At Risk 2,101
- Segment: Regular 11,002 · Budget 7,713 · New 3,294 · Premium 2,991
- AOV ₹25,726 · item margin 8.1% · review mean rating ≈ 3.6 (skewed to 3–4 stars)
- Shipments: 80,679 Delivered + 6,681 Delivered-then-Returned + 2,321 Cancelled-in-Transit ✅ ties out

## 6. Anti-leakage (from README, confirmed relevant)

- `shipments.delayed_flag`: do **not** use `actual_delivery_date` / `delivery_days` as features.
- Return modelling: `products.return_rate_baseline` is the **generator parameter** — leaky.
- Churn: `customer_status` derives from `last_order_date` → feature-cutoff discipline required.
- Order value: don't feed `order_items` into a model predicting the same order's total.

## 7. Bottom line

No data cleaning needed. The risk in this dataset is **semantic, not structural** — 8 different
columns can each quietly change your number. Fix the definitions first (§3), then analyse.

**Recommended first project:** monthly GMV / AOV trend with festival seasonality, using
`Delivered + Returned` as the revenue base, validated against `order_items` margin.
