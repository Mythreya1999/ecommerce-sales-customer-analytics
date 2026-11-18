# 01_data_cleaning.sql


✅ `DROP VIEW IF EXISTS v_valid_returns` — executed.

✅ `DROP VIEW IF EXISTS v_sales` — executed.

✅ `DROP VIEW IF EXISTS v_order_book` — executed.

✅ `DROP VIEW IF EXISTS v_orders_enriched` — executed.

✅ `DROP VIEW IF EXISTS v_zone_map` — executed.

✅ `CREATE VIEW v_zone_map AS` — executed.

✅ `CREATE VIEW v_valid_returns AS` — executed.

✅ `CREATE VIEW v_orders_enriched AS` — executed.

✅ `CREATE VIEW v_order_book AS` — executed.

✅ `CREATE VIEW v_sales AS` — executed.

### Result 11: `SELECT 'orders'                       AS check_name, COUNT(*) AS actual, 100000 AS expecte`

*10 rows returned*

| check_name                        |     actual |         expected |
|:----------------------------------|-----------:|-----------------:|
| orders                            |     100000 | 100000           |
| order_items                       |     254331 | 254331           |
| v_sales rows                      |     254331 | 254331           |
| orders_enriched rows              |     100000 | 100000           |
| realised orders                   |      87360 |  87360           |
| lost orders (Cancelled+Failed)    |      10953 |  10953           |
| valid returns                     |      11666 |  11666           |
| gross order value (Rs)            | 2500777756 |      2.50078e+09 |
| realised revenue, item level (Rs) | 2146672725 |      2.14667e+09 |
| realised profit, item level (Rs)  |  172348561 |    nan           |
