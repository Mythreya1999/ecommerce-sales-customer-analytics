"""
STEP 1 — Build the analysis base.

Reads the 9 raw CSVs from data/source/, assembles an order-item grain fact table,
applies the cleaning rules proven in DATA_AUDIT.md, and emits:
  data/raw_data.csv          - denormalised join, untouched values (what "raw" looks like)
  data/cleaned_data.csv      - analysis-ready, definitions locked
  data/powerbi/*.csv         - star schema for Power BI import
  db/ecommerce.db            - SQLite warehouse the /sql scripts run against
"""
import os, sqlite3, json
from pathlib import Path

import numpy as np
import pandas as pd

PROJ = Path(__file__).resolve().parents[1]
RAW  = PROJ / "data" / "source"
for d in ["data", "data/powerbi", "db", "sql", "python", "dashboard", "screenshots",
          "reports", "reports/figures", "reports/sql"]:
    (PROJ / d).mkdir(parents=True, exist_ok=True)

rd = lambda f, **kw: pd.read_csv(RAW / f, low_memory=False, **kw)

print("loading raw tables ...")
cust = rd("customers.csv", parse_dates=["customer_signup_date", "last_order_date"])
prod = rd("products.csv",  parse_dates=["product_launch_date"])
o    = rd("orders.csv",    parse_dates=["order_date"])
oi   = rd("order_items.csv")
pay  = rd("payments.csv",  parse_dates=["payment_date"])
sh   = rd("shipments.csv", parse_dates=["dispatch_date", "expected_delivery_date", "actual_delivery_date"])
ret  = rd("returns.csv",   parse_dates=["return_date"])
rev  = rd("customer_reviews.csv", parse_dates=["review_date"])
mk   = rd("marketing_campaigns.csv", parse_dates=["campaign_start_date", "campaign_end_date"])

# ---------------------------------------------------------------- geography
ZONE = {
 "Delhi":"North", "Haryana":"North", "Punjab":"North", "Rajasthan":"North", "Uttar Pradesh":"North",
 "Gujarat":"West", "Maharashtra":"West",
 "Andhra Pradesh":"South", "Karnataka":"South", "Kerala":"South", "Tamil Nadu":"South", "Telangana":"South",
 "Bihar":"East", "West Bengal":"East",
 "Madhya Pradesh":"Central",
}
assert set(ZONE) == set(o.delivery_state.unique()), set(o.delivery_state.unique()) - set(ZONE)

# ---------------------------------------------------------------- returns: drop impossible rows
# 402 return rows sit on Cancelled / Failed / Processing orders (never shipped) -> not a real return.
never_shipped = o.loc[o.order_status.isin(["Cancelled", "Failed", "Processing"]), "order_id"]
bad_returns = ret[ret.order_id.isin(set(never_shipped))]
ret_ok = ret[~ret.order_id.isin(set(never_shipped))].copy()
print(f"returns: {len(ret):,} raw -> {len(ret_ok):,} kept ({len(bad_returns):,} impossible rows dropped)")

# ---------------------------------------------------------------- fact: order-item grain
order_cols = ["order_id","customer_id","order_date","order_time","order_status","shipping_method",
              "delivery_city","delivery_state","coupon_code","order_discount_pct",
              "marketing_channel","subtotal","shipping_fee","tax_amount","final_amount","campaign_id"]
o = o.rename(columns={"discount_percentage": "order_discount_pct"})
prod_cols  = ["product_id","product_name","category","subcategory","brand","price","cost_price",
              "product_type","rating_average","return_rate_baseline"]
cust_cols  = ["customer_id","customer_segment","loyalty_tier","customer_status","gender","age",
              "age_group","state","city","acquisition_channel","preferred_device",
              "preferred_payment_method","total_orders","total_spend"]

f = (oi[["order_item_id","order_id","product_id","quantity","unit_price",
         "discount_percentage","item_revenue","item_cost","profit"]]
     .merge(o[order_cols], on="order_id", how="left", validate="many_to_one")
     .merge(prod[prod_cols], on="product_id", how="left", validate="many_to_one")
     .merge(cust[cust_cols], on="customer_id", how="left", validate="many_to_one"))

# payment / shipment / review / return attributes (aggregated to avoid row fan-out)
f = f.merge(pay[["order_id","payment_method","payment_status","amount_paid",
                 "transaction_fee","refund_amount"]], on="order_id", how="left", validate="many_to_one")
f = f.merge(sh[["order_id","warehouse_city","dispatch_date","expected_delivery_date",
                "actual_delivery_date","delivery_days","delivery_status","delayed_flag"]],
            on="order_id", how="left", validate="many_to_one")
rev_agg = rev.groupby(["order_id","product_id"]).agg(rating=("rating","min")).reset_index()
f = f.merge(rev_agg, on=["order_id","product_id"], how="left")
ret_agg = (ret_ok.assign(is_returned=1)
           .groupby(["order_id","product_id"])
           .agg(is_returned=("is_returned","max"), return_reason=("return_reason","first"),
                return_status=("return_status","first"), refund_amount_returns=("refund_amount","sum"))
           .reset_index())
f = f.merge(ret_agg, on=["order_id","product_id"], how="left")
f["is_returned"] = f["is_returned"].fillna(0).astype(int)
f["is_reviewed"] = f["rating"].notna().astype(int)

# ---------------------------------------------------------------- derived columns
f["order_date"] = pd.to_datetime(f["order_date"])
f["order_year"]     = f["order_date"].dt.year
f["order_quarter"]  = f["order_date"].dt.quarter
f["order_month"]    = f["order_date"].dt.month
f["order_month_name"] = f["order_date"].dt.strftime("%b")
f["order_year_month"] = f["order_date"].dt.strftime("%Y-%m")
f["order_ym_date"]  = f["order_date"].dt.to_period("M").dt.to_timestamp()
f["order_dow"]      = f["order_date"].dt.day_name()
f["order_hour"]     = pd.to_datetime(f["order_time"], format="%H:%M:%S", errors="coerce").dt.hour
f["region"]         = f["delivery_state"].map(ZONE)

f["line_revenue"] = f["item_revenue"].round(2)
f["line_cost"]    = f["item_cost"].round(2)
f["line_profit"]  = (f["line_revenue"] - f["line_cost"]).round(2)
f["margin_pct"]   = np.where(f["line_revenue"] > 0, f["line_profit"] / f["line_revenue"] * 100, 0.0)
f["gross_unit_price"] = (f["line_revenue"] / f["quantity"].replace(0, np.nan)).round(2)

# revenue status flags -> every KPI filters on these, never on raw status text
f["is_realised"]  = f["order_status"].isin(["Delivered", "Returned"]).astype(int)
f["is_delivered"] = (f["order_status"] == "Delivered").astype(int)
f["is_returned_order"] = (f["order_status"] == "Returned").astype(int)
f["is_cancelled"] = f["order_status"].isin(["Cancelled", "Failed"]).astype(int)
f["is_lost_sale"] = f["order_status"].isin(["Cancelled", "Failed"]).astype(int)

# ---------------------------------------------------------------- raw_data.csv (untouched join)
raw_out = f[[c for c in f.columns if c not in
             ("line_revenue","line_cost","line_profit","margin_pct","gross_unit_price",
              "is_realised","is_delivered","is_returned_order","is_cancelled","is_lost_sale",
              "order_year","order_quarter","order_month","order_month_name","order_year_month",
              "order_ym_date","order_dow","order_hour","region")]].copy()
raw_out.to_csv(os.path.join(PROJ, "data", "raw_data.csv"), index=False)
print(f"raw_data.csv      {raw_out.shape[0]:,} x {raw_out.shape[1]}")

# ---------------------------------------------------------------- cleaned_data.csv
drop_empty = [c for c in ["return_reason","return_status","refund_amount_returns"] if c in f]
f.to_csv(os.path.join(PROJ, "data", "cleaned_data.csv"), index=False)
print(f"cleaned_data.csv  {f.shape[0]:,} x {f.shape[1]}")

# ---------------------------------------------------------------- star schema for Power BI
PB = os.path.join(PROJ, "data", "powerbi")
dim_date = (pd.DataFrame({"date": pd.date_range("2023-01-01", "2025-12-31")})
            .assign(date_key=lambda d: d.date.dt.strftime("%Y%m%d").astype(int),
                    year=lambda d: d.date.dt.year, quarter=lambda d: d.date.dt.quarter,
                    month=lambda d: d.date.dt.month,
                    month_name=lambda d: d.date.dt.strftime("%b"),
                    month_year=lambda d: d.date.dt.strftime("%Y-%m"),
                    month_year_sort=lambda d: d.date.dt.strftime("%Y%m").astype(int),
                    week=lambda d: d.date.dt.isocalendar().week.astype(int),
                    day_name=lambda d: d.date.dt.day_name(),
                    is_weekend=lambda d: d.date.dt.dayofweek.isin([5, 6]).astype(int))
            [["date_key","date","year","quarter","month","month_name","month_year",
              "month_year_sort","week","day_name","is_weekend"]])
dim_date.to_csv(os.path.join(PB, "dim_date.csv"), index=False)

dim_customer = (cust[["customer_id","customer_segment","loyalty_tier","customer_status","gender",
                      "age","age_group","state","city","acquisition_channel","preferred_device",
                      "preferred_payment_method","customer_signup_date","first_order" if False else "total_orders",
                      "total_spend","last_order_date","average_order_value"]]
                .copy())
dim_customer["signup_year"] = pd.to_datetime(dim_customer.customer_signup_date).dt.year
dim_customer.to_csv(os.path.join(PB, "dim_customers.csv"), index=False)

dim_product = prod[["product_id","product_name","category","subcategory","brand","price",
                    "cost_price","product_type","rating_average","rating_count","stock_quantity",
                    "product_launch_date","return_rate_baseline"]].copy()
dim_product["unit_margin"] = (dim_product.price - dim_product.cost_price).round(2)
dim_product["margin_pct"]  = (dim_product.unit_margin / dim_product.price * 100).round(2)
dim_product.to_csv(os.path.join(PB, "dim_products.csv"), index=False)

fact_sales = f[["order_item_id","order_id","customer_id","product_id","order_date","order_status",
                "shipping_method","delivery_city","delivery_state","region","marketing_channel",
                "campaign_id","coupon_code","payment_method","payment_status","quantity",
                "unit_price","discount_percentage","line_revenue","line_cost","line_profit",
                "margin_pct","is_realised","is_returned","delayed_flag","rating"]].copy()
fact_sales["date_key"] = pd.to_datetime(fact_sales.order_date).dt.strftime("%Y%m%d").astype(int)
fact_sales.to_csv(os.path.join(PB, "fact_sales.csv"), index=False)

fact_returns = ret_ok.groupby("order_id").agg(
    returns=("return_id","count"), refund=("refund_amount","sum")).reset_index()
fact_returns.to_csv(os.path.join(PB, "fact_returns.csv"), index=False)
mk.to_csv(os.path.join(PB, "dim_campaigns.csv"), index=False)

# ---------------------------------------------------------------- SQLite warehouse
DB = os.path.join(PROJ, "db", "ecommerce.db")
if os.path.exists(DB):
    os.remove(DB)
con = sqlite3.connect(DB)
tables = {"customers":cust, "products":prod, "orders":o, "order_items":oi, "payments":pay,
          "shipments":sh, "returns":ret_ok, "customer_reviews":rev, "marketing_campaigns":mk}
for name, df in tables.items():
    d = df.copy()
    for c in d.columns:
        if pd.api.types.is_datetime64_any_dtype(d[c]):
            d[c] = d[c].dt.strftime("%Y-%m-%d")
    d.to_sql(name, con, index=False)
con.commit()
for (name,) in con.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
    n = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
    print(f"  sqlite {name:<22}{n:>9,}")
con.close()
print("\nBUILD OK ->", PROJ)
