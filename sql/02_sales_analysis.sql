-- =====================================================================================
-- 02_sales_analysis.sql
-- Revenue performance, product performance, margin, region, trend, seasonality.
--
-- Definition used throughout: "revenue" = SUM(line_revenue) over REALISED orders
-- (Delivered + Returned). Item-level, so it excludes shipping and tax.
-- The looser order-book figure is shown once in Q1 for reconciliation; everything
-- after that is realised.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- Q1. Headline scorecard. Also reconciles the three legitimate revenue definitions.
-- -------------------------------------------------------------------------------------
WITH kpi AS (
  SELECT
    COUNT(DISTINCT CASE WHEN is_realised = 1 THEN order_id END)        AS realised_orders,
    COUNT(DISTINCT CASE WHEN is_realised = 1 THEN customer_id END)     AS buying_customers,
    SUM(CASE WHEN is_realised = 1 THEN line_revenue  ELSE 0 END)       AS realised_revenue,
    SUM(CASE WHEN is_realised = 1 THEN line_cost     ELSE 0 END)       AS realised_cost,
    SUM(CASE WHEN is_realised = 1 THEN line_profit   ELSE 0 END)       AS realised_profit,
    SUM(line_revenue)                                                  AS revenue_all_orders,
    SUM(line_profit)                                                   AS profit_all_orders,
    SUM(CASE WHEN is_realised = 1 THEN quantity ELSE 0 END)            AS units_sold,
    COUNT(DISTINCT CASE WHEN is_lost_sale = 1 THEN order_id END)       AS lost_orders
  FROM v_sales
), merged AS (
  SELECT k.*,
         ROUND(k.realised_revenue / NULLIF(k.realised_orders, 0), 2)  AS aov_realised,
         ROUND(k.realised_profit  / NULLIF(k.realised_revenue, 0) * 100, 2) AS margin_pct,
         ROUND(k.units_sold * 1.0 / NULLIF(k.realised_orders, 0), 2)  AS units_per_order,
         ROUND(k.realised_revenue / NULLIF(k.buying_customers, 0), 2) AS revenue_per_customer
  FROM kpi k
)
SELECT 'Realised revenue (item level)'  AS metric, printf('%,.2f', realised_revenue) AS value FROM merged
UNION ALL SELECT 'Realised cost',           printf('%,.2f', realised_cost) FROM merged
UNION ALL SELECT 'Realised gross profit',   printf('%,.2f', realised_profit) FROM merged
UNION ALL SELECT 'Blended margin %',        printf('%.2f', margin_pct) FROM merged
UNION ALL SELECT 'Realised orders',         printf('%,d', realised_orders) FROM merged
UNION ALL SELECT 'Buying customers',        printf('%,d', buying_customers) FROM merged
UNION ALL SELECT 'Units sold',              printf('%,d', units_sold) FROM merged
UNION ALL SELECT 'Average order value',     printf('%,.2f', aov_realised) FROM merged
UNION ALL SELECT 'Units per order',         printf('%.2f', units_per_order) FROM merged
UNION ALL SELECT 'Revenue per customer',    printf('%,.2f', revenue_per_customer) FROM merged
UNION ALL SELECT 'Lost orders (Cancelled+Failed)', printf('%,d', lost_orders) FROM merged
UNION ALL SELECT 'Revenue if all orders counted', printf('%,.2f', revenue_all_orders) FROM merged;

-- -------------------------------------------------------------------------------------
-- Q2. Three revenue definitions side by side. This is the reconciliation exhibit.
-- -------------------------------------------------------------------------------------
SELECT 'A. All orders (order-items)'                AS definition,
       ROUND(SUM(line_revenue), 2) AS revenue, COUNT(DISTINCT order_id) AS orders
FROM v_sales
UNION ALL
SELECT 'B. Excl. Failed (order book)',
       ROUND(SUM(line_revenue), 2), COUNT(DISTINCT order_id)
FROM v_sales WHERE order_status <> 'Failed'
UNION ALL
SELECT 'C. Realised (Delivered + Returned)  <-- USED',
       ROUND(SUM(line_revenue), 2), COUNT(DISTINCT order_id)
FROM v_sales WHERE is_realised = 1;

-- -------------------------------------------------------------------------------------
-- Q3. Sales and orders by order status. Where the money is, and where it leaks.
-- -------------------------------------------------------------------------------------
SELECT order_status,
       COUNT(DISTINCT order_id)                     AS orders,
       ROUND(SUM(line_revenue), 2)                  AS item_revenue,
       ROUND(SUM(line_profit), 2)                   AS item_profit,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales), 2) AS pct_of_revenue
FROM v_sales
GROUP BY order_status
ORDER BY item_revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q4. Monthly trend with month-over-month and year-over-year growth.
-- -------------------------------------------------------------------------------------
WITH m AS (
  SELECT order_year_month,
         MIN(order_date)                       AS month_start,
         COUNT(DISTINCT order_id)              AS orders,
         COUNT(DISTINCT customer_id)           AS customers,
         SUM(line_revenue)                     AS revenue,
         SUM(line_profit)                      AS profit,
         SUM(quantity)                         AS units
  FROM v_sales
  WHERE is_realised = 1
  GROUP BY order_year_month
)
SELECT order_year_month                                    AS month,
       orders,
       customers,
       ROUND(revenue, 2)                                   AS revenue,
       ROUND(profit, 2)                                    AS profit,
       ROUND(revenue / orders, 2)                          AS aov,
       ROUND(profit / revenue * 100, 2)                    AS margin_pct,
       ROUND(revenue - LAG(revenue) OVER (ORDER BY month_start), 2) AS mom_change,
       ROUND((revenue / LAG(revenue) OVER (ORDER BY month_start) - 1) * 100, 2) AS mom_pct,
       ROUND(revenue - LAG(revenue, 12) OVER (ORDER BY month_start), 2)         AS yoy_change,
       ROUND((revenue / LAG(revenue, 12) OVER (ORDER BY month_start) - 1) * 100, 2) AS yoy_pct
FROM m
ORDER BY month;

-- -------------------------------------------------------------------------------------
-- Q5. Quarterly trend.
-- -------------------------------------------------------------------------------------
SELECT order_year || '-Q' || order_quarter        AS quarter,
       COUNT(DISTINCT order_id)                   AS orders,
       SUM(quantity)                              AS units,
       ROUND(SUM(line_revenue), 2)                AS revenue,
       ROUND(SUM(line_profit), 2)                 AS profit,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(SUM(line_revenue) * 100.0 /
             SUM(SUM(line_revenue)) OVER (), 2)   AS pct_of_total
FROM v_sales
WHERE is_realised = 1
GROUP BY order_year, order_quarter
ORDER BY order_year, order_quarter;

-- -------------------------------------------------------------------------------------
-- Q6. Seasonality: month-of-year profile (all years pooled) -- is there a seasonal shape?
-- -------------------------------------------------------------------------------------
SELECT order_month,
       CASE order_month WHEN 1 THEN 'Jan' WHEN 2 THEN 'Feb' WHEN 3 THEN 'Mar'
            WHEN 4 THEN 'Apr' WHEN 5 THEN 'May' WHEN 6 THEN 'Jun' WHEN 7 THEN 'Jul'
            WHEN 8 THEN 'Aug' WHEN 9 THEN 'Sep' WHEN 10 THEN 'Oct' WHEN 11 THEN 'Nov'
            ELSE 'Dec' END                                           AS month_name,
       COUNT(DISTINCT order_id)                                      AS orders,
       ROUND(SUM(line_revenue), 2)                                   AS revenue,
       COUNT(DISTINCT order_date)                                     AS trading_days,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_date), 2)        AS avg_revenue_per_trading_day,
       ROUND(SUM(line_revenue) / 3.0, 2)                              AS revenue_per_year_avg
FROM v_sales
WHERE is_realised = 1
GROUP BY order_month
ORDER BY order_month;

-- -------------------------------------------------------------------------------------
-- Q7. Day-of-week pattern (operational / staffing signal).
-- -------------------------------------------------------------------------------------
SELECT order_dow,
       COUNT(DISTINCT order_id)              AS orders,
       ROUND(SUM(line_revenue), 2)           AS revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov
FROM v_sales
WHERE is_realised = 1
GROUP BY order_dow
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q8. Top 20 products by realised revenue, with profit, margin and return exposure.
-- -------------------------------------------------------------------------------------
SELECT product_id,
       product_name,
       category,
       SUM(quantity)                                  AS units_sold,
       COUNT(DISTINCT order_id)                       AS orders,
       ROUND(SUM(line_revenue), 2)                    AS revenue,
       ROUND(SUM(line_profit), 2)                     AS profit,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(AVG(margin_pct), 2)                      AS avg_line_margin,
       ROUND(SUM(is_returned_item) * 100.0 / COUNT(*), 2)   AS return_rate_pct,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY product_id, product_name, category
ORDER BY revenue DESC
LIMIT 20;

-- -------------------------------------------------------------------------------------
-- Q9. Category performance: revenue, profit, margin, return rate, share.
-- -------------------------------------------------------------------------------------
SELECT category,
       COUNT(DISTINCT order_id)                        AS orders,
       SUM(quantity)                                   AS units,
       ROUND(SUM(line_revenue), 2)                     AS revenue,
       ROUND(SUM(line_profit), 2)                      AS profit,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(SUM(line_revenue) / SUM(quantity), 2)     AS avg_unit_price,
       ROUND(SUM(is_returned_item) * 100.0 / COUNT(*), 2) AS return_rate_pct,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY category
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q10. Margin ranking: which categories are actually profitable (profit margin, not revenue).
-- -------------------------------------------------------------------------------------
SELECT category,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(SUM(line_profit), 2)                            AS total_profit,
       ROUND(SUM(line_revenue), 2)                           AS total_revenue,
       COUNT(DISTINCT product_id)                            AS products,
       CASE WHEN SUM(line_profit) / SUM(line_revenue) >= 0.12 THEN 'High margin'
            WHEN SUM(line_profit) / SUM(line_revenue) >= 0.08 THEN 'Mid margin'
            ELSE 'Low margin' END                            AS margin_band
FROM v_sales
WHERE is_realised = 1
GROUP BY category
ORDER BY margin_pct DESC;

-- -------------------------------------------------------------------------------------
-- Q11. Region performance (5 demand zones) + state detail.
-- -------------------------------------------------------------------------------------
SELECT region,
       COUNT(DISTINCT order_id)                        AS orders,
       COUNT(DISTINCT customer_id)                     AS customers,
       ROUND(SUM(line_revenue), 2)                     AS revenue,
       ROUND(SUM(line_profit), 2)                      AS profit,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue,
       ROUND(AVG(delivery_days), 2)                    AS avg_delivery_days,
       ROUND(AVG(delayed_flag) * 100, 2)               AS delayed_pct
FROM v_sales
WHERE is_realised = 1
GROUP BY region
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q12. State-level detail (top 15).
-- -------------------------------------------------------------------------------------
SELECT delivery_state,
       region,
       COUNT(DISTINCT order_id)              AS orders,
       ROUND(SUM(line_revenue), 2)           AS revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2)   AS margin_pct
FROM v_sales
WHERE is_realised = 1
GROUP BY delivery_state, region
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q13. Payment method mix and its relationship to order value / failure.
-- -------------------------------------------------------------------------------------
SELECT payment_method,
       COUNT(DISTINCT order_id)                 AS orders,
       ROUND(SUM(line_revenue), 2)              AS revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY payment_method
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q14. Sales vs profit by category -- the scatter exhibit (revenue share vs margin).
-- -------------------------------------------------------------------------------------
SELECT category,
       ROUND(SUM(line_revenue), 2)                            AS revenue,
       ROUND(SUM(line_profit), 2)                             AS profit,
       ROUND(SUM(line_revenue) / SUM(SUM(line_revenue)) OVER () * 100, 2) AS revenue_share_pct,
       ROUND(SUM(line_profit)  / SUM(SUM(line_profit))  OVER () * 100, 2) AS profit_share_pct,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2)    AS margin_pct,
       CASE WHEN SUM(line_revenue) > (SELECT AVG(cat_rev) FROM
                 (SELECT SUM(line_revenue) cat_rev FROM v_sales
                  WHERE is_realised = 1 GROUP BY category))
             AND SUM(line_profit) / SUM(line_revenue) >
                 (SELECT SUM(line_profit)/SUM(line_revenue) FROM v_sales WHERE is_realised = 1)
            THEN 'Star'
            WHEN SUM(line_revenue) > (SELECT AVG(cat_rev) FROM
                 (SELECT SUM(line_revenue) cat_rev FROM v_sales
                  WHERE is_realised = 1 GROUP BY category))
            THEN 'Volume driver'
            WHEN SUM(line_profit) / SUM(line_revenue) >
                 (SELECT SUM(line_profit)/SUM(line_revenue) FROM v_sales WHERE is_realised = 1)
            THEN 'Margin niche'
            ELSE 'Underperformer' END                          AS quadrant
FROM v_sales
WHERE is_realised = 1
GROUP BY category
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q15. Discount impact: does a deeper discount buy enough volume to pay for itself?
-- -------------------------------------------------------------------------------------
SELECT item_discount_pct                                   AS discount_pct,
       COUNT(*)                                            AS line_items,
       SUM(quantity)                                       AS units,
       ROUND(SUM(line_revenue), 2)                         AS revenue,
       ROUND(SUM(line_profit), 2)                          AS profit,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(AVG(line_revenue), 2)                         AS avg_line_revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY item_discount_pct
ORDER BY item_discount_pct;

-- -------------------------------------------------------------------------------------
-- Q16. Product price band performance.
-- -------------------------------------------------------------------------------------
SELECT CASE WHEN list_price < 500    THEN '1. < Rs 500'
            WHEN list_price < 2000   THEN '2. Rs 500-2k'
            WHEN list_price < 10000  THEN '3. Rs 2k-10k'
            WHEN list_price < 30000  THEN '4. Rs 10k-30k'
            ELSE '5. Rs 30k+' END        AS price_band,
       COUNT(DISTINCT product_id)        AS products,
       SUM(quantity)                     AS units,
       ROUND(SUM(line_revenue), 2)       AS revenue,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2) AS margin_pct,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_realised = 1), 2) AS pct_of_revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY price_band
ORDER BY price_band;

-- -------------------------------------------------------------------------------------
-- Q17. Shipping method: cost, speed, delay, and value per order.
-- -------------------------------------------------------------------------------------
SELECT shipping_method,
       COUNT(DISTINCT order_id)              AS orders,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(AVG(delivery_days), 2)          AS avg_delivery_days,
       ROUND(AVG(delayed_flag) * 100, 2)     AS delayed_pct,
       ROUND(SUM(line_revenue), 2)           AS revenue
FROM v_sales
WHERE is_realised = 1
GROUP BY shipping_method
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q18. Marketing channel: attributed revenue vs realised revenue.
-- -------------------------------------------------------------------------------------
SELECT marketing_channel,
       COUNT(DISTINCT order_id)               AS orders,
       ROUND(SUM(line_revenue), 2)            AS revenue,
       ROUND(SUM(line_revenue) / COUNT(DISTINCT order_id), 2) AS aov,
       ROUND(SUM(line_profit) / SUM(line_revenue) * 100, 2)   AS margin_pct,
       ROUND(SUM(is_returned_item) * 100.0 / COUNT(*), 2)     AS return_rate_pct
FROM v_sales
WHERE is_realised = 1
GROUP BY marketing_channel
ORDER BY revenue DESC;

-- -------------------------------------------------------------------------------------
-- Q19. Pareto: how concentrated is revenue in the product catalogue?
-- -------------------------------------------------------------------------------------
WITH p AS (
  SELECT product_id, SUM(line_revenue) AS revenue
  FROM v_sales WHERE is_realised = 1 GROUP BY product_id
), r AS (
  SELECT product_id, revenue,
         ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rn,
         SUM(revenue) OVER (ORDER BY revenue DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative,
         SUM(revenue) OVER ()                      AS total,
         COUNT(*) OVER ()                          AS n_products
  FROM p
)
SELECT (SELECT n_products FROM r LIMIT 1)                                          AS total_products,
       (SELECT MIN(rn) FROM r WHERE cumulative / total >= 0.50)                    AS products_for_50pct_revenue,
       (SELECT MIN(rn) FROM r WHERE cumulative / total >= 0.80)                    AS products_for_80pct_revenue,
       (SELECT MIN(rn) FROM r WHERE cumulative / total >= 0.90)                    AS products_for_90pct_revenue,
       ROUND((SELECT MIN(rn) FROM r WHERE cumulative / total >= 0.80) * 100.0
             / (SELECT n_products FROM r LIMIT 1), 1)                              AS pct_products_for_80pct,
       ROUND((SELECT MIN(rn) FROM r WHERE cumulative / total >= 0.50) * 100.0
             / (SELECT n_products FROM r LIMIT 1), 1)                              AS pct_products_for_50pct,
       (SELECT MAX(cumulative) FROM r)                                             AS total_revenue_check
FROM (SELECT 1);

-- -------------------------------------------------------------------------------------
-- Q20. Loss analysis: what did cancellations and failures cost us?
-- -------------------------------------------------------------------------------------
SELECT order_status,
       COUNT(DISTINCT order_id)          AS orders,
       ROUND(SUM(line_revenue), 2)       AS lost_revenue,
       ROUND(AVG(line_revenue), 2)       AS avg_line_value,
       ROUND(SUM(line_revenue) * 100.0 /
             (SELECT SUM(line_revenue) FROM v_sales WHERE is_lost_sale = 1), 2) AS pct_of_loss
FROM v_sales
WHERE is_lost_sale = 1
GROUP BY order_status
ORDER BY lost_revenue DESC;
