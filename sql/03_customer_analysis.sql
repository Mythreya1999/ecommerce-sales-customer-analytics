-- =====================================================================================
-- 03_customer_analysis.sql
-- Customer value, repeat behaviour, RFM segmentation, cohort retention, churn exposure.
--
-- All customer-level metrics are built from REALISED orders only (Delivered + Returned),
-- because a cancelled order tells you nothing about customer value.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- Q1. Customer base summary: how much of the base actually buys, and how often.
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id,
         COUNT(DISTINCT order_id)     AS orders,
         SUM(line_revenue)            AS revenue,
         SUM(line_profit)             AS profit,
         MIN(order_date)              AS first_order,
         MAX(order_date)              AS last_order
  FROM v_sales
  WHERE is_realised = 1
  GROUP BY customer_id
)
SELECT COUNT(*)                                                        AS buying_customers,
       SUM(CASE WHEN orders = 1 THEN 1 ELSE 0 END)                     AS one_time_customers,
       SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                     AS repeat_customers,
       ROUND(SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS repeat_rate_pct,
       ROUND(SUM(CASE WHEN orders = 1 THEN revenue ELSE 0 END) * 100.0 / SUM(revenue), 2) AS pct_revenue_from_one_time,
       ROUND(SUM(CASE WHEN orders > 1 THEN revenue ELSE 0 END) * 100.0 / SUM(revenue), 2) AS pct_revenue_from_repeat,
       ROUND(AVG(orders), 2)                                           AS avg_orders_per_customer,
       ROUND(AVG(revenue), 2)                                          AS avg_revenue_per_customer
FROM cb;

-- -------------------------------------------------------------------------------------
-- Q2. RFM segmentation. R/F/M scored 1-5 by quintile, then mapped to named segments.
-- Recency is measured against the dataset end date (2025-12-31), since "today" is fixed.
-- -------------------------------------------------------------------------------------
WITH base AS (
  SELECT customer_id,
         COUNT(DISTINCT order_id)  AS frequency,
         SUM(line_revenue)         AS monetary,
         MAX(order_date)           AS last_order
  FROM v_sales
  WHERE is_realised = 1
  GROUP BY customer_id
), scored AS (
  SELECT customer_id, frequency, monetary, last_order,
         CAST(julianday('2025-12-31') - julianday(last_order) AS INTEGER) AS recency_days,
         NTILE(5) OVER (ORDER BY julianday('2025-12-31') - julianday(last_order) DESC) AS r_score,
         NTILE(5) OVER (ORDER BY frequency)                                            AS f_score,
         NTILE(5) OVER (ORDER BY monetary)                                             AS m_score
  FROM base
), labelled AS (
  SELECT *,
         ROUND((r_score + f_score + m_score) / 3.0, 2) AS rfm_score,
         CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
              WHEN r_score >= 3 AND f_score >= 4                  THEN '2. Loyal'
              WHEN r_score >= 4 AND f_score <= 2                  THEN '3. New / Promising'
              WHEN r_score = 3 AND f_score BETWEEN 2 AND 3        THEN '4. Needs Attention'
              WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4  THEN '5. At Risk (high value)'
              WHEN r_score <= 2 AND m_score >= 4                  THEN '6. Cannot Lose'
              WHEN r_score <= 2 AND f_score <= 2                  THEN '7. Lost'
              ELSE '8. Occasional' END AS segment
  FROM scored
)
SELECT segment,
       COUNT(*)                                     AS customers,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(SUM(monetary), 2)                      AS revenue,
       ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2) AS pct_revenue,
       ROUND(AVG(monetary), 2)                      AS avg_revenue,
       ROUND(AVG(frequency), 2)                     AS avg_orders,
       ROUND(AVG(recency_days), 0)                  AS avg_recency_days,
       ROUND(AVG(rfm_score), 2)                     AS avg_rfm_score
FROM labelled
GROUP BY segment
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q3. Top 20 highest-value customers with their behaviour profile.
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id,
         COUNT(DISTINCT order_id)  AS orders,
         SUM(line_revenue)         AS revenue,
         SUM(line_profit)          AS profit,
         MIN(order_date)           AS first_order,
         MAX(order_date)           AS last_order,
         COUNT(DISTINCT product_id) AS distinct_products
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
)
SELECT cb.customer_id,
       c.customer_segment,
       c.loyalty_tier,
       c.city,
       c.state,
       cb.orders,
       cb.distinct_products,
       ROUND(cb.revenue, 2)                       AS revenue,
       ROUND(cb.revenue / cb.orders, 2)           AS aov,
       ROUND(cb.profit / cb.revenue * 100, 2)     AS margin_pct,
       cb.first_order,
       cb.last_order,
       CAST(julianday('2025-12-31') - julianday(cb.last_order) AS INTEGER) AS days_since_last_order,
       ROUND(cb.revenue * 100.0 / (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 3) AS pct_of_total_revenue
FROM cb
JOIN customers AS c ON c.customer_id = cb.customer_id
ORDER BY cb.revenue DESC
LIMIT 20;

-- -------------------------------------------------------------------------------------
-- Q4. Pareto of customers: how concentrated is revenue in the top few?
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id, SUM(line_revenue) AS revenue
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
), r AS (
  SELECT customer_id, revenue,
         ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rn,
         SUM(revenue) OVER (ORDER BY revenue DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum,
         SUM(revenue) OVER ()                      AS total,
         COUNT(*) OVER ()                          AS n
  FROM cb
)
SELECT (SELECT n FROM r LIMIT 1)                                     AS total_buying_customers,
       (SELECT MIN(rn) FROM r WHERE cum / total >= 0.50)             AS customers_for_50pct_revenue,
       (SELECT MIN(rn) FROM r WHERE cum / total >= 0.80)             AS customers_for_80pct_revenue,
       ROUND((SELECT MIN(rn) FROM r WHERE cum / total >= 0.80) * 100.0
             / (SELECT n FROM r LIMIT 1), 1)                         AS pct_customers_for_80pct,
       ROUND((SELECT MIN(rn) FROM r WHERE cum / total >= 0.50) * 100.0
             / (SELECT n FROM r LIMIT 1), 1)                         AS pct_customers_for_50pct
FROM (SELECT 1);

-- -------------------------------------------------------------------------------------
-- Q5. One-time vs repeat: is a repeat customer actually worth more?
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id,
         COUNT(DISTINCT order_id) AS orders,
         SUM(line_revenue)        AS revenue,
         SUM(line_profit)         AS profit,
         MIN(order_date)          AS first_order,
         MAX(order_date)          AS last_order
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
)
SELECT CASE WHEN orders = 1            THEN '1. One-time'
            WHEN orders BETWEEN 2 AND 3 THEN '2. Repeat 2-3'
            WHEN orders BETWEEN 4 AND 6 THEN '3. Repeat 4-6'
            ELSE '4. Repeat 7+' END              AS loyalty_band,
       COUNT(*)                                  AS customers,
       ROUND(AVG(orders), 2)                     AS avg_orders,
       ROUND(AVG(revenue), 2)                    AS avg_customer_revenue,
       ROUND(SUM(revenue), 2)                    AS total_revenue,
       ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (), 2) AS pct_revenue,
       ROUND(AVG(profit) / AVG(revenue) * 100, 2) AS margin_pct,
       ROUND(AVG(julianday(last_order) - julianday(first_order)), 0) AS avg_lifespan_days
FROM cb
GROUP BY loyalty_band
ORDER BY loyalty_band;

-- -------------------------------------------------------------------------------------
-- Q6. Customer segment performance (Premium / Regular / Budget / New).
-- -------------------------------------------------------------------------------------
SELECT customer_segment,
       COUNT(DISTINCT customer_id)                       AS customers,
       COUNT(DISTINCT order_id)                          AS orders,
       ROUND(SUM(line_revenue), 2)                       AS revenue,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2)      AS aov,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT customer_id), 2)   AS revenue_per_customer,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2)        AS margin_pct,
       ROUND(SUM(is_returned_item) * 100.0 / COUNT(*), 2)          AS return_rate_pct,
       ROUND(AVG(delivery_days), 2)                                AS avg_delivery_days
FROM v_sales
WHERE is_realised = 1
GROUP BY customer_segment
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q7. Loyalty tier performance.
-- -------------------------------------------------------------------------------------
SELECT loyalty_tier,
       COUNT(DISTINCT customer_id)              AS customers,
       ROUND(SUM(line_revenue), 2)              AS revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT customer_id), 2) AS revenue_per_customer,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2)    AS aov,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2)      AS margin_pct
FROM v_sales
WHERE is_realised = 1
GROUP BY loyalty_tier
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q8. Acquisition channel quality: which channel brings customers worth keeping?
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id,
         COUNT(DISTINCT order_id) AS orders,
         SUM(line_revenue)        AS revenue
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
)
SELECT c.acquisition_channel,
       COUNT(DISTINCT c.customer_id)                              AS customers_acquired,
       COUNT(DISTINCT CASE WHEN cb.orders > 0 THEN c.customer_id END) AS customers_who_bought,
       ROUND(COUNT(DISTINCT CASE WHEN cb.orders > 0 THEN c.customer_id END) * 100.0
             / COUNT(DISTINCT c.customer_id), 2)                  AS activation_rate_pct,
       ROUND(SUM(COALESCE(cb.orders, 0)) * 1.0 /
             NULLIF(COUNT(DISTINCT CASE WHEN cb.orders > 0 THEN c.customer_id END), 0), 2) AS avg_orders,
       ROUND(AVG(CASE WHEN cb.orders > 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS repeat_rate_pct,
       ROUND(SUM(COALESCE(cb.revenue, 0)), 2)                     AS revenue,
       ROUND(SUM(COALESCE(cb.revenue, 0)) /
             NULLIF(COUNT(DISTINCT CASE WHEN cb.orders > 0 THEN c.customer_id END), 0), 2) AS revenue_per_buyer
FROM customers AS c
LEFT JOIN cb ON cb.customer_id = c.customer_id
GROUP BY c.acquisition_channel
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q9. Cohort retention: signup-month cohort, share still ordering N months later.
-- Only cohorts with a full 12 months of observation are shown.
-- -------------------------------------------------------------------------------------
WITH first_order AS (
  SELECT customer_id, MIN(order_date) AS first_order_date
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
), cohort AS (
  SELECT customer_id,
         strftime('%Y-%m', first_order_date) AS cohort_month
  FROM first_order
), activity AS (
  SELECT s.customer_id,
         co.cohort_month,
         s.order_year_month AS activity_month,
         (CAST(strftime('%Y', s.order_date) AS INTEGER) - CAST(substr(co.cohort_month,1,4) AS INTEGER)) * 12
         + (CAST(strftime('%m', s.order_date) AS INTEGER) - CAST(substr(co.cohort_month,6,2) AS INTEGER)) AS month_offset
  FROM v_sales AS s
  JOIN cohort AS co ON co.customer_id = s.customer_id
  WHERE s.is_realised = 1
), sizes AS (
  SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size FROM cohort GROUP BY cohort_month
), matrix AS (
  SELECT a.cohort_month, a.month_offset,
         COUNT(DISTINCT a.customer_id) AS active
  FROM activity AS a
  WHERE a.month_offset BETWEEN 0 AND 12
  GROUP BY a.cohort_month, a.month_offset
)
SELECT m.cohort_month,
       s.cohort_size,
       ROUND(MAX(CASE WHEN m.month_offset = 0  THEN m.active * 100.0 / s.cohort_size END), 1) AS m0_pct,
       ROUND(MAX(CASE WHEN m.month_offset = 1  THEN m.active * 100.0 / s.cohort_size END), 1) AS m1_pct,
       ROUND(MAX(CASE WHEN m.month_offset = 3  THEN m.active * 100.0 / s.cohort_size END), 1) AS m3_pct,
       ROUND(MAX(CASE WHEN m.month_offset = 6  THEN m.active * 100.0 / s.cohort_size END), 1) AS m6_pct,
       ROUND(MAX(CASE WHEN m.month_offset = 9  THEN m.active * 100.0 / s.cohort_size END), 1) AS m9_pct,
       ROUND(MAX(CASE WHEN m.month_offset = 12 THEN m.active * 100.0 / s.cohort_size END), 1) AS m12_pct
FROM matrix AS m
JOIN sizes  AS s ON s.cohort_month = m.cohort_month
GROUP BY m.cohort_month, s.cohort_size
ORDER BY m.cohort_month;

-- -------------------------------------------------------------------------------------
-- Q10. Order-frequency distribution: how many customers order 1, 2, 3 ... times?
-- -------------------------------------------------------------------------------------
WITH cb AS (
  SELECT customer_id, COUNT(DISTINCT order_id) AS orders
  FROM v_sales WHERE is_realised = 1 GROUP BY customer_id
)
SELECT CASE WHEN orders >= 10 THEN '10+' ELSE CAST(orders AS TEXT) END AS orders_placed,
       COUNT(*) AS customers,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(SUM(COUNT(*)) OVER (ORDER BY MIN(orders) DESC) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS cumulative_pct
FROM cb
GROUP BY orders_placed
ORDER BY MIN(orders) DESC;

-- -------------------------------------------------------------------------------------
-- Q11. Churn exposure: where is revenue sitting on customers who stopped buying?
-- -------------------------------------------------------------------------------------
SELECT customer_status,
       COUNT(DISTINCT customer_id)              AS customers,
       COUNT(DISTINCT order_id)                 AS orders,
       ROUND(SUM(line_revenue), 2)              AS historical_revenue,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT customer_id), 2) AS revenue_per_customer,
       ROUND(AVG(julianday('2025-12-31') - julianday(order_date)), 0) AS avg_days_since_order
FROM v_sales
WHERE is_realised = 1
GROUP BY customer_status
ORDER BY historical_revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q12. Purchase cadence: days between consecutive orders, by repeat depth.
-- -------------------------------------------------------------------------------------
WITH seq AS (
  SELECT customer_id,
         order_date,
         LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS prev_order
  FROM (SELECT DISTINCT customer_id, order_id, order_date FROM v_sales WHERE is_realised = 1)
), gaps AS (
  SELECT customer_id,
         CAST(julianday(order_date) - julianday(prev_order) AS INTEGER) AS gap_days
  FROM seq WHERE prev_order IS NOT NULL
)
SELECT CASE WHEN gap_days <= 7    THEN '1. <= 7 days'
            WHEN gap_days <= 30   THEN '2. 8-30 days'
            WHEN gap_days <= 60   THEN '3. 31-60 days'
            WHEN gap_days <= 120  THEN '4. 61-120 days'
            ELSE '5. 120+ days' END     AS gap_band,
       COUNT(*)                          AS order_pairs,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct,
       ROUND(AVG(gap_days), 1)           AS avg_gap_days
FROM gaps
GROUP BY gap_band
ORDER BY gap_band;

-- -------------------------------------------------------------------------------------
-- Q13. Category mix by customer segment -- what does each segment actually buy?
-- -------------------------------------------------------------------------------------
SELECT customer_segment,
       category,
       ROUND(SUM(line_revenue), 2)  AS revenue,
       ROUND(SUM(line_revenue) * 100.0 / SUM(SUM(line_revenue))
             OVER (PARTITION BY customer_segment), 2) AS pct_of_segment_revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov
FROM v_sales
WHERE is_realised = 1
GROUP BY customer_segment, category
ORDER BY customer_segment, revenue DESC;
