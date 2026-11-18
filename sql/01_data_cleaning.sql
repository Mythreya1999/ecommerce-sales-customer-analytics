-- =====================================================================================
-- 01_data_cleaning.sql
-- E-Commerce Sales & Customer Analytics  |  SQLite warehouse: db/ecommerce.db
--
-- Purpose: turn the 9 raw base tables into one governed analytics view so that every
--          downstream KPI uses the SAME definition. Nothing here mutates raw data.
--
-- Four definitional decisions are locked here (see DATA_AUDIT.md §3):
--   1. Revenue base  = orders with status IN ('Delivered','Returned')  -> "realised revenue"
--      (Cancelled + Failed = 10,953 orders / Rs 71.8 Cr that were never realised)
--      A second, looser base ("gross order value", excludes Failed only) is kept for
--      order-book reporting and is exposed as v_order_book.
--   2. returns   -> 409 rows sit on Cancelled/Failed/Processing orders (never shipped).
--                   These are logically impossible and are excluded from v_valid_returns.
--   3. order-level discount_percentage is NOT applied to final_amount (subtotal is already
--      net of the item-level discount). It is carried as order_discount_pct, descriptive
--      only, and must never be multiplied against subtotal.
--   4. payment amount_paid = 0 for Failed/Not Charged/Pending by design -> revenue is
--      measured from order_items, never from amount_paid.
-- =====================================================================================

DROP VIEW IF EXISTS v_valid_returns;
DROP VIEW IF EXISTS v_sales;
DROP VIEW IF EXISTS v_order_book;
DROP VIEW IF EXISTS v_orders_enriched;

-- -------------------------------------------------------------------------------------
-- Geography: 15 delivery states rolled up to 5 demand zones.
-- -------------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_zone_map;
CREATE VIEW v_zone_map AS
SELECT 'Delhi'          AS state, 'North'   AS region UNION ALL
SELECT 'Haryana',        'North'            UNION ALL
SELECT 'Punjab',         'North'            UNION ALL
SELECT 'Rajasthan',      'North'            UNION ALL
SELECT 'Uttar Pradesh',  'North'            UNION ALL
SELECT 'Gujarat',        'West'             UNION ALL
SELECT 'Maharashtra',    'West'             UNION ALL
SELECT 'Andhra Pradesh', 'South'            UNION ALL
SELECT 'Karnataka',      'South'            UNION ALL
SELECT 'Kerala',         'South'            UNION ALL
SELECT 'Tamil Nadu',     'South'            UNION ALL
SELECT 'Telangana',      'South'            UNION ALL
SELECT 'Bihar',          'East'             UNION ALL
SELECT 'West Bengal',    'East'             UNION ALL
SELECT 'Madhya Pradesh', 'Central';

-- -------------------------------------------------------------------------------------
-- Returns that are physically possible: the order must have shipped.
-- 12,075 raw rows -> 11,666 valid (409 dropped).
-- -------------------------------------------------------------------------------------
CREATE VIEW v_valid_returns AS
SELECT r.return_id,
       r.order_id,
       r.customer_id,
       r.product_id,
       r.return_date,
       r.return_reason,
       r.refund_amount,
       r.return_status
FROM returns AS r
JOIN orders  AS o ON o.order_id = r.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Failed', 'Processing');

-- -------------------------------------------------------------------------------------
-- Order-level enrichment. One row per order. Used by both sales and customer analysis.
-- -------------------------------------------------------------------------------------
CREATE VIEW v_orders_enriched AS
SELECT o.order_id,
       o.customer_id,
       o.order_date,
       CAST(strftime('%Y', o.order_date) AS INTEGER)  AS order_year,
       CAST(strftime('%m', o.order_date) AS INTEGER)  AS order_month,
       strftime('%Y-%m', o.order_date)                AS order_year_month,
       CAST(((CAST(strftime('%m', o.order_date) AS INTEGER) - 1) / 3 + 1) AS INTEGER) AS order_quarter,
       CASE strftime('%w', o.order_date)
            WHEN '0' THEN 'Sunday'    WHEN '1' THEN 'Monday'  WHEN '2' THEN 'Tuesday'
            WHEN '3' THEN 'Wednesday' WHEN '4' THEN 'Thursday' WHEN '5' THEN 'Friday'
            ELSE 'Saturday' END                       AS order_dow,
       o.order_status,
       o.shipping_method,
       o.delivery_city,
       o.delivery_state,
       COALESCE(z.region, 'Central')                  AS region,
       o.marketing_channel,
       o.campaign_id,
       o.coupon_code,
       o.order_discount_pct,
       o.subtotal,
       o.shipping_fee,
       o.tax_amount,
       o.final_amount,
       c.customer_segment,
       c.loyalty_tier,
       c.customer_status,
       c.gender,
       c.age_group,
       c.acquisition_channel,
       c.preferred_device,
       p.payment_method,
       p.payment_status,
       p.amount_paid,
       s.delivery_days,
       s.delayed_flag,
       -- ---- governed flags: every KPI filters on these, never on raw status text ----
       CASE WHEN o.order_status IN ('Delivered','Returned') THEN 1 ELSE 0 END AS is_realised,
       CASE WHEN o.order_status = 'Delivered'  THEN 1 ELSE 0 END AS is_delivered,
       CASE WHEN o.order_status = 'Returned'   THEN 1 ELSE 0 END AS is_returned_order,
       CASE WHEN o.order_status IN ('Cancelled','Failed') THEN 1 ELSE 0 END AS is_lost_sale
FROM orders AS o
JOIN customers   AS c ON c.customer_id = o.customer_id
JOIN payments    AS p ON p.order_id    = o.order_id
LEFT JOIN shipments AS s ON s.order_id = o.order_id
LEFT JOIN v_zone_map AS z ON z.state   = o.delivery_state;

-- -------------------------------------------------------------------------------------
-- v_order_book: the looser revenue base (excludes Failed only). For order-book reporting.
-- -------------------------------------------------------------------------------------
CREATE VIEW v_order_book AS
SELECT *
FROM v_orders_enriched
WHERE order_status <> 'Failed';

-- -------------------------------------------------------------------------------------
-- v_sales: THE core fact view. Grain = one order line item (~254,331 rows).
-- Revenue and profit are always line_revenue / line_profit from order_items, because
-- orders.final_amount includes shipping + tax and would overstate merchandise margin.
-- -------------------------------------------------------------------------------------
CREATE VIEW v_sales AS
SELECT oi.order_item_id,
       oi.order_id,
       oi.product_id,
       oi.quantity,
       oi.unit_price,
       oi.discount_percentage                    AS item_discount_pct,
       ROUND(oi.item_revenue, 2)                 AS line_revenue,
       ROUND(oi.item_cost, 2)                    AS line_cost,
       ROUND(oi.item_revenue - oi.item_cost, 2)  AS line_profit,
       CASE WHEN oi.item_revenue > 0
            THEN ROUND((oi.item_revenue - oi.item_cost) / oi.item_revenue * 100, 2)
            ELSE 0 END                           AS margin_pct,
       pr.product_name,
       pr.category,
       pr.subcategory,
       pr.brand,
       pr.product_type,
       pr.price                                 AS list_price,
       pr.cost_price,
       oe.customer_id,
       oe.order_date,
       oe.order_year,
       oe.order_month,
       oe.order_year_month,
       oe.order_quarter,
       oe.order_dow,
       oe.order_status,
       oe.shipping_method,
       oe.delivery_city,
       oe.delivery_state,
       oe.region,
       oe.marketing_channel,
       oe.coupon_code,
       oe.customer_segment,
       oe.loyalty_tier,
       oe.customer_status,
       oe.gender,
       oe.age_group,
       oe.acquisition_channel,
       oe.preferred_device,
       oe.payment_method,
       oe.payment_status,
       oe.delayed_flag,
       oe.delivery_days,
       oe.is_realised,
       oe.is_delivered,
       oe.is_returned_order,
       oe.is_lost_sale,
       CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END AS is_returned_item
FROM order_items AS oi
JOIN v_orders_enriched AS oe ON oe.order_id = oi.order_id
JOIN products   AS pr      ON pr.product_id = oi.product_id
LEFT JOIN (SELECT order_id, product_id, MIN(return_id) AS return_id
           FROM v_valid_returns
           GROUP BY order_id, product_id) AS r
       ON r.order_id = oi.order_id AND r.product_id = oi.product_id;

-- -------------------------------------------------------------------------------------
-- Post-build integrity gate. Every value below must match the audited baseline.
-- -------------------------------------------------------------------------------------
SELECT 'orders'                       AS check_name, COUNT(*) AS actual, 100000 AS expected FROM orders
UNION ALL SELECT 'order_items',                COUNT(*), 254331 FROM order_items
UNION ALL SELECT 'v_sales rows',               COUNT(*), 254331 FROM v_sales
UNION ALL SELECT 'orders_enriched rows',       COUNT(*), 100000 FROM v_orders_enriched
UNION ALL SELECT 'realised orders',            COUNT(*), 87360  FROM v_orders_enriched WHERE is_realised = 1
UNION ALL SELECT 'lost orders (Cancelled+Failed)', COUNT(*), 10953 FROM v_orders_enriched WHERE is_lost_sale = 1
UNION ALL SELECT 'valid returns',              COUNT(*), 11666  FROM v_valid_returns
UNION ALL SELECT 'gross order value (Rs)',
                 CAST(ROUND(SUM(final_amount)) AS INTEGER), 2500777756 FROM v_order_book
UNION ALL SELECT 'realised revenue, item level (Rs)',
                 CAST(ROUND(SUM(line_revenue)) AS INTEGER), 2146672725 FROM v_sales WHERE is_realised = 1
UNION ALL SELECT 'realised profit, item level (Rs)',
                 CAST(ROUND(SUM(line_profit)) AS INTEGER), NULL FROM v_sales WHERE is_realised = 1;
