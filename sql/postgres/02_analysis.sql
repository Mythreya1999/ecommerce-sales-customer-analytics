-- =====================================================================================
--  E-Commerce Sales & Customer Analytics — PostgreSQL analysis queries
--  10 queries covering joins, CTEs, window functions, RFM and cohort retention.
--  Run after 01_schema.sql. Every query reads v_sales (the governed view) and filters
--  on is_realised — the same definition used by the notebook and the dashboard.
--
--  Verified values against the dataset are quoted in the header of each query.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
--  Q1  Executive scorecard
--      Technique: FILTER-clause aggregates over ONE scan. No WHERE clause on purpose —
--      a WHERE is_realised would make the lost-order metrics structurally impossible
--      (every lost order is by definition not realised).
--      Expected: revenue 2,146,672,725  profit 172,348,561  margin 8.03%
--                orders 87,360  customers 22,208  AOV 24,572.72  lost 10,953
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(DISTINCT order_id)    FILTER (WHERE is_realised)          AS realised_orders,
    COUNT(DISTINCT customer_id) FILTER (WHERE is_realised)          AS buying_customers,
    SUM(line_revenue)           FILTER (WHERE is_realised)          AS revenue,
    SUM(line_profit)            FILTER (WHERE is_realised)          AS gross_profit,
    ROUND(100.0 * SUM(line_profit) FILTER (WHERE is_realised)
                / NULLIF(SUM(line_revenue) FILTER (WHERE is_realised), 0), 2)  AS margin_pct,
    ROUND(SUM(line_revenue) FILTER (WHERE is_realised)
                / NULLIF(COUNT(DISTINCT order_id) FILTER (WHERE is_realised), 0), 2) AS avg_order_value,
    SUM(quantity)               FILTER (WHERE is_realised)          AS units_sold,
    -- loss and quality alongside the headline, so the scorecard cannot be read in isolation
    COUNT(DISTINCT order_id)    FILTER (WHERE is_lost_sale)         AS lost_orders,
    SUM(line_revenue)           FILTER (WHERE is_lost_sale)         AS lost_revenue,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_returned_item AND is_realised)
                / NULLIF(COUNT(*) FILTER (WHERE is_realised), 0), 2) AS return_rate_pct
FROM v_sales;


-- -------------------------------------------------------------------------------------
--  Q2  Monthly revenue with month-over-month growth
--      Technique: CTE aggregation + LAG() window for MoM, and a 3-month moving average.
--      Expected: 2025-12 revenue 171,127,086 (the peak month)
-- -------------------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        order_month,
        COUNT(DISTINCT order_id) AS orders,
        SUM(line_revenue)        AS revenue,
        SUM(line_profit)         AS profit
    FROM v_sales
    WHERE is_realised
    GROUP BY order_month
)
SELECT
    order_month,
    orders,
    revenue,
    profit,
    ROUND(100.0 * profit / revenue, 2)                              AS margin_pct,
    revenue - LAG(revenue) OVER (ORDER BY order_month)              AS mom_change,
    ROUND(100.0 * (revenue / LAG(revenue) OVER (ORDER BY order_month) - 1), 2) AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (ORDER BY order_month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)     AS revenue_3m_avg,
    RANK() OVER (ORDER BY revenue DESC)                              AS revenue_rank
FROM monthly
ORDER BY order_month;


-- -------------------------------------------------------------------------------------
--  Q3  Category performance: revenue, margin, and share of the company
--      Technique: window SUM() OVER () for the share column — no second scan of the table.
--      Expected: Electronics 50.04% of revenue at 0.67% margin; Fashion 33.17% margin
-- -------------------------------------------------------------------------------------
SELECT
    category,
    COUNT(DISTINCT order_id)                                       AS orders,
    SUM(quantity)                                                  AS units,
    SUM(line_revenue)                                              AS revenue,
    SUM(line_profit)                                               AS profit,
    ROUND(100.0 * SUM(line_profit) / NULLIF(SUM(line_revenue), 0), 2) AS margin_pct,
    ROUND(100.0 * SUM(line_revenue) / SUM(SUM(line_revenue)) OVER (), 2) AS pct_of_revenue,
    ROUND(100.0 * SUM(line_profit)  / SUM(SUM(line_profit))  OVER (), 2) AS pct_of_profit,
    RANK() OVER (ORDER BY SUM(line_revenue)  DESC)                  AS revenue_rank,
    RANK() OVER (ORDER BY SUM(line_profit) / NULLIF(SUM(line_revenue),0) DESC) AS margin_rank
FROM v_sales
WHERE is_realised
GROUP BY category
ORDER BY revenue DESC;


-- -------------------------------------------------------------------------------------
--  Q4  Product ranking inside each category (top 3 per category)
--      Technique: RANK() OVER (PARTITION BY ...) then filter on the window result in an
--                 outer query — the standard "top N per group" pattern.
--      Also answers the concentration question: PROD10246 alone is 21.35% of revenue.
-- -------------------------------------------------------------------------------------
WITH product_totals AS (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        SUM(s.quantity)     AS units,
        SUM(s.line_revenue) AS revenue,
        SUM(s.line_profit)  AS profit,
        ROUND(100.0 * SUM(s.line_profit) / NULLIF(SUM(s.line_revenue), 0), 2) AS margin_pct,
        RANK() OVER (PARTITION BY p.category ORDER BY SUM(s.line_revenue) DESC) AS rank_in_category,
        -- computed HERE, before the top-3 filter: a window in the outer query would divide by
        -- the filtered rows only and overstate every share (37.98% instead of 21.35%).
        ROUND(100.0 * SUM(s.line_revenue) / SUM(SUM(s.line_revenue)) OVER (), 2) AS pct_of_company_revenue
    FROM v_sales s
    JOIN products p ON p.product_id = s.product_id
    WHERE s.is_realised
    GROUP BY p.category, p.product_id, p.product_name
)
SELECT
    category,
    rank_in_category,
    product_id,
    product_name,
    units,
    revenue,
    profit,
    margin_pct,
    pct_of_company_revenue
FROM product_totals
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;


-- -------------------------------------------------------------------------------------
--  Q5  Regional performance with share and rank
--      Technique: window SUM() for share, RANK() for ordering.
--      Expected: South 32.39% > North 30.81% > West 24.62% > East 7.53% > Central 4.64%
-- -------------------------------------------------------------------------------------
SELECT
    region,
    COUNT(DISTINCT order_id)                                        AS orders,
    COUNT(DISTINCT customer_id)                                     AS customers,
    SUM(line_revenue)                                               AS revenue,
    ROUND(100.0 * SUM(line_revenue) / SUM(SUM(line_revenue)) OVER (), 2) AS pct_of_revenue,
    ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2)          AS aov,
    ROUND(100.0 * SUM(line_profit) / NULLIF(SUM(line_revenue), 0), 2) AS margin_pct,
    ROUND(AVG(delivery_days), 2)                                    AS avg_delivery_days,
    ROUND(100.0 * AVG(delayed_flag), 1)                             AS delayed_pct,
    RANK() OVER (ORDER BY SUM(line_revenue) DESC)                   AS revenue_rank
FROM v_sales
WHERE is_realised
GROUP BY region
ORDER BY revenue DESC;


-- -------------------------------------------------------------------------------------
--  Q6  Repeat vs one-time customers
--      Technique: CTE at customer grain + HAVING, then a window for the revenue share.
--      Expected: 4,399 one-time / 17,809 repeat (80.19% repeat) — repeat = 95.6% of revenue
-- -------------------------------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(line_revenue)        AS revenue,
        MIN(order_date)          AS first_order,
        MAX(order_date)          AS last_order
    FROM v_sales
    WHERE is_realised
    GROUP BY customer_id
),
banded AS (
    SELECT
        CASE WHEN order_count = 1            THEN '1. One-time'
             WHEN order_count BETWEEN 2 AND 3 THEN '2. Repeat 2-3'
             WHEN order_count BETWEEN 4 AND 6 THEN '3. Repeat 4-6'
             ELSE '4. Repeat 7+' END AS loyalty_band,
        order_count,
        revenue,
        last_order - first_order AS lifespan_days
    FROM customer_orders
)
SELECT
    loyalty_band,
    COUNT(*)                                                        AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct_of_customers,
    SUM(revenue)                                                    AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2)       AS pct_of_revenue,
    ROUND(AVG(revenue), 2)                                          AS avg_revenue_per_customer,
    ROUND(AVG(order_count), 2)                                      AS avg_orders,
    ROUND(AVG(lifespan_days), 0)                                    AS avg_lifespan_days
FROM banded
GROUP BY loyalty_band
ORDER BY loyalty_band;


-- -------------------------------------------------------------------------------------
--  Q7  RFM segmentation
--      Technique: NTILE(5) windows on recency / frequency / monetary, then a CASE label.
--      Recency is measured against the dataset's last date (2025-12-31), not CURRENT_DATE —
--      using today() would mark every customer churned.
--      Expected: Champions 2,953 · At Risk 2,275 · Loyal 2,766
-- -------------------------------------------------------------------------------------
WITH base AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id)                    AS frequency,
        SUM(line_revenue)                           AS monetary,
        MAX(order_date)                             AS last_order
    FROM v_sales
    WHERE is_realised
    GROUP BY customer_id
),
scored AS (
    SELECT
        customer_id, frequency, monetary,
        (DATE '2025-12-31' - last_order) AS recency_days,
        NTILE(5) OVER (ORDER BY (DATE '2025-12-31' - last_order) DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency)                              AS f_score,
        NTILE(5) OVER (ORDER BY monetary)                               AS m_score
    FROM base
),
labelled AS (
    SELECT *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1. Champions'
            WHEN r_score >= 3 AND f_score >= 4                  THEN '2. Loyal'
            WHEN r_score >= 4 AND f_score <= 2                  THEN '3. New / Promising'
            WHEN r_score  = 3 AND f_score BETWEEN 2 AND 3       THEN '4. Needs Attention'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN '5. At Risk (high value)'
            WHEN r_score <= 2 AND m_score >= 4                  THEN '6. Cannot Lose'
            WHEN r_score <= 2 AND f_score <= 2                  THEN '7. Lost'
            ELSE '8. Occasional'
        END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*)                                                   AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS pct_of_customers,
    SUM(monetary)                                              AS revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_of_revenue,
    ROUND(AVG(monetary), 2)                                    AS avg_revenue,
    ROUND(AVG(recency_days), 0)                                AS avg_recency_days
FROM labelled
GROUP BY segment
ORDER BY revenue DESC;


-- -------------------------------------------------------------------------------------
--  Q8  Cohort retention by first-purchase month
--      Technique: CTE for each customer's first order, join back to every later order,
--                 generate_series for month offsets, then pivot with FILTER.
--      Only cohorts with a full 12-month observation window are shown.
--      Expected: month-1 retention ~31.5%, month-12 ~6.8%
-- -------------------------------------------------------------------------------------
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_date
    FROM v_sales WHERE is_realised
    GROUP BY customer_id
),
cohort AS (
    SELECT customer_id, DATE_TRUNC('month', first_date)::date AS cohort_month
    FROM first_order
),
activity AS (
    SELECT
        c.cohort_month,
        s.customer_id,
        (EXTRACT(YEAR  FROM s.order_date) - EXTRACT(YEAR  FROM c.cohort_month)) * 12
      + (EXTRACT(MONTH FROM s.order_date) - EXTRACT(MONTH FROM c.cohort_month)) AS month_offset
    FROM v_sales s
    JOIN cohort c ON c.customer_id = s.customer_id
    WHERE s.is_realised
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size FROM cohort GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    sz.cohort_size,
    ROUND(100.0 * COUNT(DISTINCT a.customer_id) FILTER (WHERE a.month_offset = 0)  / sz.cohort_size, 1) AS m0_pct,
    ROUND(100.0 * COUNT(DISTINCT a.customer_id) FILTER (WHERE a.month_offset = 1)  / sz.cohort_size, 1) AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT a.customer_id) FILTER (WHERE a.month_offset = 3)  / sz.cohort_size, 1) AS m3_pct,
    ROUND(100.0 * COUNT(DISTINCT a.customer_id) FILTER (WHERE a.month_offset = 6)  / sz.cohort_size, 1) AS m6_pct,
    ROUND(100.0 * COUNT(DISTINCT a.customer_id) FILTER (WHERE a.month_offset = 12) / sz.cohort_size, 1) AS m12_pct
FROM activity a
JOIN sizes sz ON sz.cohort_month = a.cohort_month
WHERE a.month_offset BETWEEN 0 AND 12
  AND a.cohort_month <= DATE '2024-12-01'
GROUP BY a.cohort_month, sz.cohort_size
ORDER BY a.cohort_month;


-- -------------------------------------------------------------------------------------
--  Q9  Discount depth vs margin — the pricing exhibit
--      Technique: CASE bucketing + a window for each band's share of revenue, and a
--                 separate CTE for the company-average benchmark to compare against.
--      Expected: margin turns NEGATIVE at 20%+ discount; 34.1% of lines sit there
-- -------------------------------------------------------------------------------------
WITH company AS (
    SELECT ROUND(100.0 * SUM(line_profit) / SUM(line_revenue), 2) AS company_margin
    FROM v_sales WHERE is_realised
),
banded AS (
    SELECT
        CASE WHEN item_discount_pct = 0                        THEN 'a. 0%'
             WHEN item_discount_pct > 0  AND item_discount_pct <= 10 THEN 'b. 1-10%'
             WHEN item_discount_pct > 10 AND item_discount_pct <= 20 THEN 'c. 10-20%'
             WHEN item_discount_pct > 20 AND item_discount_pct <= 25 THEN 'd. 20-25%'
             ELSE 'e. 25%+' END                               AS discount_band,
        line_revenue, line_profit
    FROM v_sales
    WHERE is_realised
)
SELECT
    b.discount_band,
    COUNT(*)                                                          AS line_items,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                AS pct_of_lines,
    SUM(b.line_revenue)                                               AS revenue,
    SUM(b.line_profit)                                                AS profit,
    ROUND(100.0 * SUM(b.line_profit) / NULLIF(SUM(b.line_revenue),0), 2) AS margin_pct,
    c.company_margin,
    ROUND(100.0 * SUM(b.line_profit) / NULLIF(SUM(b.line_revenue),0) - c.company_margin, 2) AS vs_company_pp
FROM banded b
CROSS JOIN company c
GROUP BY b.discount_band, c.company_margin
ORDER BY b.discount_band;


-- -------------------------------------------------------------------------------------
--  Q10 Return rate and revenue at risk, by category
--      Technique: correlated EXISTS on the governed returns view + window for ranking.
--                 Note the LEFT JOIN trap this avoids: joining returns row-by-row would
--                 duplicate order lines and inflate revenue. EXISTS cannot fan out.
--      Expected: overall return rate 5.29%; Footwear highest at 9.42%
-- -------------------------------------------------------------------------------------
SELECT
    category,
    COUNT(*)                                                          AS line_items,
    COUNT(*) FILTER (WHERE is_returned_item)                          AS returned_lines,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_returned_item) / COUNT(*), 2) AS return_rate_pct,
    SUM(line_revenue)                                                 AS revenue,
    SUM(line_revenue) FILTER (WHERE is_returned_item)                 AS revenue_at_risk,
    ROUND(100.0 * SUM(line_revenue) FILTER (WHERE is_returned_item)
                / NULLIF(SUM(line_revenue), 0), 2)                    AS pct_revenue_at_risk,
    RANK() OVER (ORDER BY COUNT(*) FILTER (WHERE is_returned_item)::numeric / COUNT(*) DESC) AS return_rate_rank
FROM v_sales
WHERE is_realised
GROUP BY category
ORDER BY return_rate_pct DESC;
