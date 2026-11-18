# Data directory

## `source/` — committed

The nine raw CSVs exactly as delivered (55 MB total), plus the documentation that came with them:

| File | What it is |
|---|---|
| `customers.csv`, `products.csv`, `orders.csv`, `order_items.csv`, `payments.csv`, `shipments.csv`, `returns.csv`, `customer_reviews.csv`, `marketing_campaigns.csv` | the nine source tables |
| `generate_dataset.py` | the deterministic generator (seed 42) that produced the dataset |
| `data_dictionary.csv` | column-level documentation for all 106 columns |
| `DATA_AUDIT.md` | the data-quality audit — integrity checks and definitional traps |
| `README.md` | the dataset publisher's own description |

**This dataset is 100% synthetic.** No real person, company or transaction is represented. It is
released under CC0.

## Everything else — generated, not committed

| File | Size | Why excluded |
|---|---:|---|
| `raw_data.csv` | 126 MB | exceeds GitHub's 100 MB per-file hard limit |
| `cleaned_data.csv` | 153 MB | exceeds GitHub's 100 MB per-file hard limit |
| `powerbi/fact_sales.csv` | 54 MB | derivable; keeps the clone light |
| `../db/ecommerce.db` | 59 MB | derivable; binary |

Rebuild all four with:

```bash
pip install -r requirements.txt
python python/build_pipeline.py
```

The committed `powerbi/dim_*.csv` and `fact_returns.csv` are small and used directly by the
Power BI build guide; `fact_sales.csv` is the one import file you have to generate.
