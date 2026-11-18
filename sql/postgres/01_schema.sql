-- =====================================================================================
--  E-Commerce Sales & Customer Analytics — PostgreSQL schema
--  Target: PostgreSQL 14+   |   Load: COPY from the CSVs in data/source/
--
--  Design notes
--    * Money is NUMERIC(14,2), not FLOAT — sums of floats drift and a finance reviewer will notice.
--    * Every table has a real primary key; every foreign key is declared, so a bad load fails loudly
--      instead of silently orphaning rows.
--    * Dates are DATE (order time lives in its own TIME column).
--    * Indexes are created on the join keys and the date column that every query filters on.
-- =====================================================================================

DROP VIEW  IF EXISTS v_sales CASCADE;
DROP VIEW  IF EXISTS v_valid_returns CASCADE;
DROP TABLE IF EXISTS returns CASCADE;
DROP TABLE IF EXISTS shipments CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS campaigns CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- -------------------------------------------------------------------------------------
-- Dimensions
-- -------------------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id              VARCHAR(16)  PRIMARY KEY,
    customer_signup_date     DATE         NOT NULL,
    gender                   VARCHAR(12),
    age                      NUMERIC(4,1) CHECK (age IS NULL OR (age BETWEEN 0 AND 120)),
    age_group                VARCHAR(16),
    state                    VARCHAR(48)  NOT NULL,
    city                     VARCHAR(48)  NOT NULL,
    pincode_prefix           INTEGER,
    customer_segment         VARCHAR(16)  NOT NULL,
    preferred_device         VARCHAR(24),
    preferred_payment_method VARCHAR(24),
    acquisition_channel      VARCHAR(32),
    total_orders             INTEGER      NOT NULL DEFAULT 0 CHECK (total_orders >= 0),
    total_spend              NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_spend >= 0),
    last_order_date          DATE,
    average_order_value      NUMERIC(14,2),
    customer_status          VARCHAR(20)  NOT NULL,
    loyalty_tier             VARCHAR(16)  NOT NULL
);

CREATE TABLE products (
    product_id             VARCHAR(16)  PRIMARY KEY,
    product_name           VARCHAR(120) NOT NULL,
    category               VARCHAR(40)  NOT NULL,
    subcategory            VARCHAR(48),
    brand                  VARCHAR(64),
    price                  NUMERIC(12,2) NOT NULL CHECK (price > 0),
    cost_price             NUMERIC(12,2) NOT NULL CHECK (cost_price >= 0),
    discount_range         VARCHAR(24),
    rating_average         NUMERIC(3,2),
    rating_count           INTEGER,
    stock_quantity         INTEGER,
    product_launch_date    DATE,
    product_type           VARCHAR(20),
    return_rate_baseline   NUMERIC(5,4)
);

CREATE TABLE campaigns (
    campaign_id          VARCHAR(16) PRIMARY KEY,
    campaign_name        VARCHAR(80),
    channel              VARCHAR(40),
    campaign_start_date  DATE,
    campaign_end_date    DATE,
    campaign_type        VARCHAR(32),
    target_segment       VARCHAR(16),
    discount_percentage  INTEGER,
    conversions          INTEGER,
    revenue_generated    NUMERIC(14,2),
    impressions          BIGINT,
    clicks               INTEGER,
    campaign_cost        NUMERIC(14,2),
    roi                  NUMERIC(8,3)
);

-- -------------------------------------------------------------------------------------
-- Facts
-- -------------------------------------------------------------------------------------
CREATE TABLE orders (
    order_id             VARCHAR(16) PRIMARY KEY,
    customer_id          VARCHAR(16) NOT NULL REFERENCES customers (customer_id),
    order_date           DATE        NOT NULL,
    order_time           TIME,
    order_status         VARCHAR(16) NOT NULL
                         CHECK (order_status IN ('Delivered','Returned','Cancelled','Failed','Processing')),
    shipping_method      VARCHAR(24),
    delivery_city        VARCHAR(48),
    delivery_state       VARCHAR(48),
    coupon_code          VARCHAR(24),
    discount_percentage  NUMERIC(5,2) NOT NULL DEFAULT 0,
    marketing_channel    VARCHAR(32),
    subtotal             NUMERIC(14,2) NOT NULL CHECK (subtotal >= 0),
    shipping_fee         NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    tax_amount           NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    final_amount         NUMERIC(14,2) NOT NULL CHECK (final_amount >= 0),
    campaign_id          VARCHAR(16)
);

CREATE TABLE order_items (
    order_item_id       VARCHAR(20) PRIMARY KEY,
    order_id            VARCHAR(16) NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    product_id          VARCHAR(16) NOT NULL REFERENCES products (product_id),
    quantity            INTEGER     NOT NULL CHECK (quantity > 0),
    unit_price          NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    discount_percentage NUMERIC(5,2) NOT NULL DEFAULT 0,
    item_revenue        NUMERIC(14,2) NOT NULL CHECK (item_revenue >= 0),
    item_cost           NUMERIC(14,2) NOT NULL CHECK (item_cost >= 0),
    profit              NUMERIC(14,2) NOT NULL
);

CREATE TABLE payments (
    payment_id       VARCHAR(16) PRIMARY KEY,
    order_id         VARCHAR(16) NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    payment_date     DATE,
    payment_method   VARCHAR(24) NOT NULL,
    payment_status   VARCHAR(16) NOT NULL,
    amount_paid      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    transaction_fee  NUMERIC(10,2) NOT NULL DEFAULT 0,
    refund_amount    NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (refund_amount >= 0)
);

CREATE TABLE shipments (
    shipment_id             VARCHAR(16) PRIMARY KEY,
    order_id                VARCHAR(16) NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    warehouse_city          VARCHAR(48),
    delivery_city           VARCHAR(48),
    shipping_method         VARCHAR(24),
    dispatch_date           DATE,
    expected_delivery_date  DATE,
    actual_delivery_date    DATE,
    delivery_days           NUMERIC(5,1),
    delivery_status         VARCHAR(28),
    delayed_flag            SMALLINT NOT NULL DEFAULT 0
);

CREATE TABLE returns (
    return_id      VARCHAR(16) PRIMARY KEY,
    order_id       VARCHAR(16) NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    customer_id    VARCHAR(16) NOT NULL REFERENCES customers (customer_id),
    product_id     VARCHAR(16) NOT NULL REFERENCES products (product_id),
    return_date    DATE,
    return_reason  VARCHAR(40),
    refund_amount  NUMERIC(14,2) NOT NULL DEFAULT 0,
    return_status  VARCHAR(20)
);

-- -------------------------------------------------------------------------------------
-- Indexes: the join keys and the date every query filters on
-- -------------------------------------------------------------------------------------
CREATE INDEX idx_orders_customer      ON orders (customer_id);
CREATE INDEX idx_orders_date          ON orders (order_date);
CREATE INDEX idx_orders_status        ON orders (order_status);
CREATE INDEX idx_orders_state         ON orders (delivery_state);
CREATE INDEX idx_items_order          ON order_items (order_id);
CREATE INDEX idx_items_product        ON order_items (product_id);
CREATE INDEX idx_items_order_product  ON order_items (order_id, product_id);
CREATE INDEX idx_payments_order       ON payments (order_id);
CREATE INDEX idx_shipments_order      ON shipments (order_id);
CREATE INDEX idx_returns_order        ON returns (order_id);
CREATE INDEX idx_returns_product      ON returns (product_id);
CREATE INDEX idx_products_category    ON products (category);
CREATE INDEX idx_customers_segment    ON customers (customer_segment);

-- =====================================================================================
--  Governed view layer — the SAME definitions as sql/01_data_cleaning.sql (SQLite)
--  Every KPI filters on a flag below; nothing filters on raw status text.
-- =====================================================================================

-- 409 return rows sit on orders that never shipped (Cancelled / Failed / Processing).
-- They are physically impossible and are excluded from every return metric.
CREATE VIEW v_valid_returns AS
SELECT r.*
FROM returns r
JOIN orders o ON o.order_id = r.order_id
WHERE o.order_status NOT IN ('Cancelled', 'Failed', 'Processing');

-- One row per order line, with the order, product and customer dimensions attached
-- plus the boolean flags the analysis layer filters on.
CREATE VIEW v_sales AS
SELECT
    oi.order_item_id,
    oi.order_id,
    oi.product_id,
    oi.quantity,
    oi.unit_price,
    oi.discount_percentage              AS item_discount_pct,
    oi.item_revenue                     AS line_revenue,
    oi.item_cost                        AS line_cost,
    oi.profit                           AS line_profit,
    p.product_name,
    p.category,
    p.subcategory,
    p.brand,
    p.product_type,
    p.price                             AS list_price,
    o.customer_id,
    o.order_date,
    DATE_TRUNC('month', o.order_date)::date          AS order_month,
    EXTRACT(YEAR  FROM o.order_date)::int            AS order_year,
    EXTRACT(QUARTER FROM o.order_date)::int          AS order_quarter,
    o.order_status,
    o.shipping_method,
    o.delivery_city,
    o.delivery_state,
    CASE o.delivery_state
        WHEN 'Delhi' THEN 'North' WHEN 'Haryana' THEN 'North' WHEN 'Punjab' THEN 'North'
        WHEN 'Rajasthan' THEN 'North' WHEN 'Uttar Pradesh' THEN 'North'
        WHEN 'Gujarat' THEN 'West' WHEN 'Maharashtra' THEN 'West'
        WHEN 'Andhra Pradesh' THEN 'South' WHEN 'Karnataka' THEN 'South'
        WHEN 'Kerala' THEN 'South' WHEN 'Tamil Nadu' THEN 'South' WHEN 'Telangana' THEN 'South'
        WHEN 'Bihar' THEN 'East' WHEN 'West Bengal' THEN 'East'
        ELSE 'Central'
    END                                 AS region,
    o.marketing_channel,
    o.coupon_code,
    c.customer_segment,
    c.loyalty_tier,
    c.customer_status,
    c.acquisition_channel,
    pay.payment_method,
    pay.payment_status,
    sh.delayed_flag,
    sh.delivery_days,
    -- governed flags
    (o.order_status IN ('Delivered','Returned'))      AS is_realised,
    (o.order_status = 'Delivered')                    AS is_delivered,
    (o.order_status = 'Returned')                     AS is_returned_order,
    (o.order_status IN ('Cancelled','Failed'))        AS is_lost_sale,
    EXISTS (SELECT 1 FROM v_valid_returns vr
            WHERE vr.order_id = oi.order_id AND vr.product_id = oi.product_id) AS is_returned_item
FROM order_items oi
JOIN orders    o   ON o.order_id    = oi.order_id
JOIN products  p   ON p.product_id  = oi.product_id
JOIN customers c   ON c.customer_id = o.customer_id
LEFT JOIN payments  pay ON pay.order_id = o.order_id
LEFT JOIN shipments sh  ON sh.order_id  = o.order_id;

-- -------------------------------------------------------------------------------------
-- Integrity gate — mirrors the SQLite one. Every row must read PASS.
-- -------------------------------------------------------------------------------------
SELECT 'customers'        AS check_name, COUNT(*) AS actual, 25000 AS expected FROM customers
UNION ALL SELECT 'products',        COUNT(*), 550        FROM products
UNION ALL SELECT 'orders',          COUNT(*), 100000     FROM orders
UNION ALL SELECT 'order_items',     COUNT(*), 254331     FROM order_items
UNION ALL SELECT 'v_sales rows',    COUNT(*), 254331     FROM v_sales
UNION ALL SELECT 'valid returns',   COUNT(*), 11666      FROM v_valid_returns
UNION ALL SELECT 'realised orders',
                 COUNT(DISTINCT order_id), 87360         FROM v_sales WHERE is_realised
UNION ALL SELECT 'realised revenue (₹)',
                 ROUND(SUM(line_revenue)), 2146672725    FROM v_sales WHERE is_realised;
