"""
Load the e-commerce CSVs into PostgreSQL and execute the analysis queries.

    python sql/postgres/load.py            # load + verify + run queries
    python sql/postgres/load.py --run-only # skip load, just re-run queries

Writes reports/sql/postgres_results.md with every result set.
Connection defaults to localhost:5433 (the dev cluster); override with PG* env vars.
"""
import os
import sys
from pathlib import Path

import psycopg

PROJ = Path(__file__).resolve().parents[2]
RAW = PROJ / "data" / "source"
SQL_DIR = PROJ / "sql" / "postgres"
OUT = PROJ / "reports" / "sql" / "postgres_results.md"

DSN = dict(
    host=os.environ.get("PGHOST", "localhost"),
    # 5432 = a standard PostgreSQL install. The verification run in this repo used a
    # disposable cluster on 5433, so set PGPORT=5433 to reproduce it exactly.
    port=int(os.environ.get("PGPORT", "5432")),
    user=os.environ.get("PGUSER", "postgres"),
    dbname=os.environ.get("PGDATABASE", "ecommerce"),
    password=os.environ.get("PGPASSWORD") or None,
)

# (table, csv, columns) — column lists match the DDL exactly
TABLES = [
    ("customers", "customers.csv", "customer_id,customer_signup_date,gender,age,age_group,state,city,"
                                   "pincode_prefix,customer_segment,preferred_device,preferred_payment_method,"
                                   "acquisition_channel,total_orders,total_spend,last_order_date,"
                                   "average_order_value,customer_status,loyalty_tier"),
    ("products", "products.csv", "product_id,product_name,category,subcategory,brand,price,cost_price,"
                                 "discount_range,rating_average,rating_count,stock_quantity,"
                                 "product_launch_date,product_type,return_rate_baseline"),
    ("campaigns", "marketing_campaigns.csv", "campaign_id,campaign_name,channel,campaign_start_date,"
                                             "campaign_end_date,campaign_type,target_segment,"
                                             "discount_percentage,conversions,revenue_generated,"
                                             "impressions,clicks,campaign_cost,roi"),
    ("orders", "orders.csv", "order_id,customer_id,order_date,order_time,order_status,shipping_method,"
                             "delivery_city,delivery_state,coupon_code,discount_percentage,"
                             "marketing_channel,subtotal,shipping_fee,tax_amount,final_amount,campaign_id"),
    ("order_items", "order_items.csv", "order_item_id,order_id,product_id,quantity,unit_price,"
                                       "discount_percentage,item_revenue,item_cost,profit"),
    ("payments", "payments.csv", "payment_id,order_id,payment_date,payment_method,payment_status,"
                                 "amount_paid,transaction_fee,refund_amount"),
    ("shipments", "shipments.csv", "shipment_id,order_id,warehouse_city,delivery_city,shipping_method,"
                                   "dispatch_date,expected_delivery_date,actual_delivery_date,"
                                   "delivery_days,delivery_status,delayed_flag"),
    ("returns", "returns.csv", "return_id,order_id,customer_id,product_id,return_date,return_reason,"
                               "refund_amount,return_status"),
]


def split_statements(sql: str):
    """Split on semicolons that are outside quotes and not on a comment-only line."""
    out, buf, in_str = [], [], False
    for line in sql.splitlines():
        buf.append(line)
        in_str ^= (line.count("'") % 2 == 1)
        if not in_str and line.rstrip().endswith(";"):
            out.append("\n".join(buf))
            buf = []
    tail = "\n".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def run_script(con, path, skip_after=None):
    sql = Path(path).read_text(encoding="utf-8")
    if skip_after:
        sql = sql.split(skip_after)[0]
    ok = bad = 0
    # DDL runs in autocommit: a failing statement must not roll back the DROPs that
    # preceded it, or the next run finds half the objects still there.
    prev, con.autocommit = con.autocommit, True
    try:
        for st in split_statements(sql):
            body = "\n".join(l for l in st.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
            if not body:
                continue
            try:
                con.execute(body)
                ok += 1
            except Exception as e:
                bad += 1
                print(f"   ERROR: {str(e).splitlines()[0][:150]}")
    finally:
        con.autocommit = prev
    return ok, bad


def load(con):
    print("creating schema …")
    ok, bad = run_script(con, SQL_DIR / "01_schema.sql", skip_after="-- Integrity gate")
    print(f"  DDL statements ok={ok} errors={bad}")

    print("loading CSVs …")
    with con.cursor() as cur:
        for table, csv, cols in TABLES:
            p = (RAW / csv).resolve()
            with open(p, "r", encoding="utf-8") as fh:
                with cur.copy(f"COPY {table} ({cols}) FROM STDIN WITH (FORMAT csv, HEADER true, "
                              f"NULL '', ENCODING 'UTF8')") as cp:
                    for chunk in iter(lambda: fh.read(1 << 20), ""):
                        cp.write(chunk)
            con.commit()
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            print(f"  {table:<14} {cur.fetchone()[0]:>9,} rows")

    # ANALYZE so the planner has stats before the analysis queries
    con.execute("ANALYZE")
    con.commit()


def run_queries(con):
    sql = (SQL_DIR / "02_analysis.sql").read_text(encoding="utf-8")
    blocks = [b for b in sql.split("-- -----------------------------------------------------------------------------------")
              if b.strip() and "SELECT" in b]
    out = ["# PostgreSQL analysis results\n",
           f"*Executed against `{DSN['dbname']}` on {DSN['host']}:{DSN['port']} — "
           f"PostgreSQL {con.info.server_version}*\n"]
    n_ok = n_bad = 0
    for i, b in enumerate(blocks, 1):
        body = "\n".join(l for l in b.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
        m = [l for l in b.splitlines() if l.strip().startswith("-- ")]
        title = next((l.strip("- ").strip() for l in m if l.strip().startswith("--  Q")), f"Query {i}")
        try:
            cur = con.execute(body)
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            out.append(f"\n## {title}\n")
            out.append(f"*{len(rows):,} rows*\n")
            hdr = "| " + " | ".join(cols) + " |"
            sep = "|" + "|".join(["---"] * len(cols)) + "|"
            out.append(hdr); out.append(sep)
            for r in rows[:60]:
                cells = []
                for v in r:
                    if v is None:
                        cells.append("")
                    elif isinstance(v, float):
                        cells.append(f"{v:,.2f}")
                    else:
                        cells.append(str(v))
                out.append("| " + " | ".join(cells) + " |")
            if len(rows) > 60:
                out.append(f"\n*… {len(rows)-60} more rows*")
            n_ok += 1
            print(f"  Q{i:<2} ok   {title[:60]}")
        except Exception as e:
            n_bad += 1
            msg = str(e).splitlines()[0][:200]
            out.append(f"\n## {title}\n\n**ERROR:** `{msg}`\n")
            print(f"  Q{i:<2} FAIL {title[:60]} -> {msg}")
            con.rollback()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"\nqueries ok={n_ok} errors={n_bad} -> {OUT}")


def main():
    run_only = "--run-only" in sys.argv
    with psycopg.connect(**DSN) as con:
        if not run_only:
            load(con)
        print("\nintegrity gate:")
        with con.cursor() as cur:
            cur.execute("""SELECT 'customers' AS check_name, COUNT(*) AS actual, 25000 AS expected FROM customers
                UNION ALL SELECT 'orders',        COUNT(*), 100000 FROM orders
                UNION ALL SELECT 'order_items',   COUNT(*), 254331 FROM order_items
                UNION ALL SELECT 'v_sales rows',  COUNT(*), 254331 FROM v_sales
                UNION ALL SELECT 'valid returns', COUNT(*), 11666  FROM v_valid_returns
                UNION ALL SELECT 'realised revenue (Rs)',
                               ROUND(SUM(line_revenue))::bigint, 2146672725 FROM v_sales WHERE is_realised""")
            for name, act, exp in cur.fetchall():
                flag = "PASS" if act == exp else "FAIL"
                print(f"  [{flag}] {name:<24}{act:>14,}  expected {exp:>14,}")
        print()
        run_queries(con)


if __name__ == "__main__":
    main()
