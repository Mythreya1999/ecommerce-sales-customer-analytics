"""Execute a .sql file against db/ecommerce.db and render every result set to markdown."""
import os, re, sqlite3, sys
from pathlib import Path

import pandas as pd

pd.set_option("display.float_format", lambda x: f"{x:,.2f}")
pd.set_option("display.max_columns", 40)
pd.set_option("display.width", 250)

PROJ = str(Path(__file__).resolve().parents[1])
DB   = os.path.join(PROJ, "db", "ecommerce.db")

def split_statements(sql: str):
    """Split on ';' at end of line, ignoring comments and quoted text."""
    stmts, buf = [], []
    in_str = False
    for line in sql.splitlines():
        stripped = line.strip()
        buf.append(line)
        # toggle string state on single quotes (no escapes used in these files)
        for ch in line:
            if ch == "'":
                in_str = not in_str
        if not in_str and stripped.endswith(";") and not stripped.startswith("--"):
            stmts.append("\n".join(buf).strip())
            buf = []
    tail = "\n".join(buf).strip()
    if tail and not all(l.strip().startswith("--") or not l.strip() for l in tail.splitlines()):
        stmts.append(tail)
    return stmts

def run(path, show_all=True):
    sql = open(path, encoding="utf-8").read()
    con = sqlite3.connect(DB)
    out = [f"# {os.path.basename(path)}\n"]
    ok = fail = 0
    for i, stmt in enumerate(split_statements(sql), 1):
        body = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
        if not body:
            continue
        try:
            cur = con.execute(body)
            if cur.description:
                cols = [d[0] for d in cur.description]
                rows = cur.fetchall()
                df = pd.DataFrame(rows, columns=cols)
                head = body.splitlines()[0][:90]
                out.append(f"\n### Result {i}: `{head}`\n")
                out.append(f"*{len(df):,} rows returned*\n")
                if show_all or len(df) <= 60:
                    out.append(df.to_markdown(index=False))
                else:
                    out.append(df.head(40).to_markdown(index=False))
                    out.append(f"\n*... {len(df)-40} more rows*")
                out.append("")
            else:
                ok += 1
                out.append(f"\n✅ `{body.splitlines()[0][:90]}` — executed.")
            con.commit()
        except Exception as e:
            fail += 1
            out.append(f"\n❌ **ERROR** in statement {i}: `{e}`\n```sql\n{body[:500]}\n```")
    con.close()
    txt = "\n".join(out)
    dest = os.path.join(PROJ, "reports", "sql", os.path.basename(path).replace(".sql", ".md"))
    open(dest, "w", encoding="utf-8").write(txt)
    print(f"{os.path.basename(path):<28} statements_ok={ok} errors={fail} -> {dest}")
    if fail:
        for line in txt.splitlines():
            if "ERROR" in line:
                print("   ", line.strip())
    return ok, fail

if __name__ == "__main__":
    targets = sys.argv[1:] or ["sql/01_data_cleaning.sql"]
    tot_f = 0
    for t in targets:
        p = os.path.join(PROJ, t) if not os.path.isabs(t) else t
        _, f = run(p)
        tot_f += f
    sys.exit(1 if tot_f else 0)
