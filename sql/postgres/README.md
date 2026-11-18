# PostgreSQL layer

The analysis, in a real relational database rather than a file. This is the version to screen —
correct types, declared keys, governed views, and window functions.

**Verified:** schema + 10 queries executed against **PostgreSQL 16.16** on 2026-11-15. All 8 tables
loaded, integrity gate 6/6 PASS, 10/10 queries returned results. Output is captured in
`../../reports/sql/postgres_results.md`.

---

## Files

| File | What it is |
|---|---|
| `01_schema.sql` | DDL: 8 tables, 9 foreign keys, CHECK constraints, 13 indexes, 2 governed views, integrity gate |
| `02_analysis.sql` | 10 business queries (see table below) |
| `load.py` | Loads the CSVs with `COPY`, runs the gate, executes the queries, writes the markdown report |

## Query inventory

| # | Query | Techniques |
|---|---|---|
| 1 | Executive scorecard | `FILTER (WHERE …)` aggregates, one scan |
| 2 | Monthly revenue | CTE · `LAG()` for month-over-month · `ROWS BETWEEN` moving average · `RANK()` |
| 3 | Category performance | `SUM() OVER ()` share · two `RANK()` orderings |
| 4 | Top 3 products per category | `RANK() OVER (PARTITION BY …)` then filter |
| 5 | Regional performance | `SUM() OVER ()` share · `RANK()` |
| 6 | Repeat vs one-time customers | CTE at customer grain · `HAVING`-free banding · window share |
| 7 | RFM segmentation | `NTILE(5)` on recency / frequency / monetary |
| 8 | Cohort retention | CTE for first order · month-offset join · `FILTER` pivot |
| 9 | Discount band vs margin | `CASE` bucketing · `CROSS JOIN` to a company-average CTE |
| 10 | Return rate by category | `EXISTS` on the returns view (avoids the fan-out a join would cause) |

## Run it

```bash
# against your own PostgreSQL install (default port 5432)
export PGPASSWORD='your-postgres-password'      # or omit if your pg_hba trusts local
createdb -h localhost -p 5432 -U postgres ecommerce
python load.py              # schema + COPY + gate + queries
python load.py --run-only   # re-run the queries only
```

Connection defaults: `localhost:5432`, user `postgres`, database `ecommerce`.
Override with `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE`.

> **About the verification run.** The numbers in `../../reports/sql/postgres_results.md` were produced
> on a **disposable cluster on port 5433** (trust auth, no password) because the machine's standard
> install on 5432 is password-protected and no credential was supplied. Same server version (16.16),
> same schema, same data — reproduce with `PGPORT=5433` if that cluster is still running, or against
> your own instance.

The CSVs are read from `data/source/` (the raw drop). Nothing is written back to the source data.

## Design decisions worth defending in an interview

**`NUMERIC`, not `FLOAT`, for money.** `FLOAT` accumulates binary rounding error across 254,331 rows.
A finance reviewer notices ₹0.03 drift; `NUMERIC(14,2)` makes it impossible.

**`age` and `delivery_days` are `NUMERIC`, not `INTEGER`.** The source CSVs store them as `44.0` and
`6.0`. Declaring them `SMALLINT` makes `COPY` fail with
`invalid input syntax for type smallint: "44.0"`. Changing the type is the honest fix; silently
truncating the values is not.

**The governed view, not repeated `WHERE` clauses.** `v_sales` carries `is_realised`,
`is_lost_sale` and `is_returned_item`. Every query filters on a flag. If the definition of "revenue"
ever changes, it changes in one line of one view — not in ten queries.

**`EXISTS` instead of a join for the return flag.** Joining `returns` to `order_items` on
`order_id` duplicates rows wherever an order has more than one return line, inflating both revenue
and return count. `EXISTS` is a semi-join: it cannot fan out.

**Two traps this file hit and fixed — worth knowing:**
- A `WHERE is_realised` on the scorecard makes `lost_orders` structurally **always zero**, because no
  lost order is ever realised. Loss metrics need `FILTER (WHERE is_lost_sale)` over the unfiltered
  table.
- A `SUM() OVER ()` share computed in the *outer* query after a `WHERE rank <= 3` divides by the
  filtered rows only. The top product showed **37.98%** of company revenue instead of **21.35%**.
  Window shares must be computed in the CTE, before the filter.

## Retiring the dev cluster

The instance used for verification was a throwaway cluster in the agent scratch directory on port
5433. It is disposable — `load.py` rebuilds everything from the CSVs. To stop it:

```bash
pg_ctl -D <datadir> stop -m fast
```
