"""
Build dashboard v3 — fixes from review:

  1. KEY INSIGHTS strip at the top (the recruiter-facing conclusion, not just charts)
  2. RETURN RATE KPI + net-of-returns revenue (answers "why are returns in revenue?")
  3. MONTHLY TREND split into revenue (own axis) and margin % (own chart) — kills the
     misleading dual axis where an 8% line looked equal to a 100% line
  4. PROVENANCE stated on the page, not only in the README
     (plus v2's fixes: fluid layout, working slicers, exact distinct order/customer counts)
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd

PROJ = Path(__file__).resolve().parents[1]
df = pd.read_csv(PROJ / "data" / "cleaned_data.csv", parse_dates=["order_date"], low_memory=False)
d = df[df.is_realised == 1].copy()

# ---------------------------------------------------------------- dimension codes
years  = sorted(d.order_year.unique().tolist())
cats   = sorted(d.category.unique().tolist())
regs   = ["South", "North", "West", "East", "Central"]
segs   = ["Regular", "Budget", "Premium", "New"]
pays   = d.groupby("payment_method").line_revenue.sum().sort_values(ascending=False).index.tolist()
Y = {v: i for i, v in enumerate(years)}
C = {v: i for i, v in enumerate(cats)}
R = {v: i for i, v in enumerate(regs)}
S = {v: i for i, v in enumerate(segs)}
Pm = {v: i for i, v in enumerate(pays)}

prod_ids = sorted(d.product_id.unique().tolist())
PI = {v: i for i, v in enumerate(prod_ids)}
pu = d.drop_duplicates("product_id").set_index("product_id")
prod_list = [[str(pu.loc[p, "product_name"]), C[pu.loc[p, "category"]]] for p in prod_ids]

cust_ids = sorted(d.customer_id.unique().tolist())
CI = {v: i for i, v in enumerate(cust_ids)}
ord_ids = sorted(d.order_id.unique().tolist())
OI = {v: i for i, v in enumerate(ord_ids)}

# ---------------------------------------------------------------- cube 1: main
# [y, m, cat, reg, seg, revenue, profit, units, lines, returns, [cust], [ord]]
g = d.groupby(["order_year", "order_month", "category", "region", "customer_segment"], observed=True)
main = []
for (y, m, c, r, s), sub in g:
    main.append([Y[y], m - 1, C[c], R[r], S[s],
                 int(round(sub.line_revenue.sum())),
                 int(round(sub.line_profit.sum())),
                 int(sub.quantity.sum()),
                 int(len(sub)),
                 int(sub.is_returned.sum()),
                 sorted({CI[x] for x in sub.customer_id.unique()}),
                 sorted({OI[x] for x in sub.order_id.unique()})])

# ---------------------------------------------------------------- cube 2: product
g2 = d.groupby(["order_year", "region", "customer_segment", "product_id"], observed=True)
prod = [[Y[y], R[r], S[s], PI[p], int(round(sub.line_revenue.sum())), int(round(sub.line_profit.sum()))]
        for (y, r, s, p), sub in g2]

# ---------------------------------------------------------------- cube 3: payment
g3 = d.groupby(["order_year", "category", "region", "customer_segment", "payment_method"], observed=True)
pay = [[Y[y], C[c], R[r], S[s], Pm[pm], int(round(sub.line_revenue.sum()))]
       for (y, c, r, s, pm), sub in g3]

print(f"cubes: main {len(main):,} | product {len(prod):,} | payment {len(pay):,}")

# ---------------------------------------------------------------- headline facts (verified)
yr = d.groupby("order_year").agg(rev=("line_revenue", "sum"), ord=("order_id", "nunique"))
cat = d.groupby("category").agg(rev=("line_revenue", "sum"), prof=("line_profit", "sum"))
cat["mg"] = cat.prof / cat.rev * 100
reg = d.groupby("region").line_revenue.sum()
top3 = reg[["South", "North", "West"]].sum() / reg.sum() * 100
sku = d[d.product_id == "PROD10246"]

FACTS = {
    "rev":            float(d.line_revenue.sum()),
    "profit":         float(d.line_profit.sum()),
    "margin":         float(d.line_profit.sum() / d.line_revenue.sum() * 100),
    "rv2023":         float(yr.rev[2023]), "rv2024": float(yr.rev[2024]), "rv2025": float(yr.rev[2025]),
    "yoy25":          float((yr.rev[2025] / yr.rev[2024] - 1) * 100),
    "ord_growth":     float((yr.ord[2025] / yr.ord[2024] - 1) * 100),
    "aov23":          float(yr.rev[2023] / yr.ord[2023]),
    "aov25":          float(yr.rev[2025] / yr.ord[2025]),
    "elec_rev":       float(cat.rev["Electronics"]), "elec_prof": float(cat.prof["Electronics"]),
    "elec_mg":        float(cat.mg["Electronics"]),
    "fash_rev":       float(cat.rev["Fashion"]), "fash_prof": float(cat.prof["Fashion"]),
    "fash_mg":        float(cat.mg["Fashion"]),
    "top3_share":     float(top3),
    "sku_rev":        float(sku.line_revenue.sum()),
    "sku_share":      float(sku.line_revenue.sum() / d.line_revenue.sum() * 100),
    "sku_profit_share": float(sku.line_profit.sum() / d.line_profit.sum() * 100),
    "sku_mg":         float(sku.line_profit.sum() / sku.line_revenue.sum() * 100),
    "return_rate":    float(d.is_returned.mean() * 100),
    "rev_ex_returns": float(d[d.order_status == "Delivered"].line_revenue.sum()),
    "returned_rev":   float(d[d.order_status == "Returned"].line_revenue.sum()),
    "customers":      int(d.customer_id.nunique()),
    "orders":         int(d.order_id.nunique()),
}

DATA = {
    "years": years, "months": list(range(1, 13)), "cats": cats, "regs": regs, "segs": segs,
    "pays": pays, "prods": prod_list, "main": main, "prodCube": prod, "payCube": pay,
    "facts": FACTS,
}


def _safe(o):
    if isinstance(o, np.integer):
        return int(o)
    if isinstance(o, np.floating):
        return float(o)
    return str(o)


payload = json.dumps(DATA, separators=(",", ":"), default=_safe)
print(f"payload {len(payload)/1024/1024:.2f} MB")

# =====================================================================================
HTML = r"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>E-Commerce Sales &amp; Customer Dashboard</title>
<style>
  :root{
    --ink:#1B2733; --muted:#5B6B7C; --line:#E4E9EF; --bg:#F4F6F9; --card:#FFFFFF;
    --blue:#2E5A88; --blue2:#5D8CB8; --orange:#E8833A; --green:#4B9B6B; --red:#B5495B;
    --grey:#9DB4CC; --gold:#B8862B;
  }
  *{box-sizing:border-box;}
  html,body{margin:0;padding:0;width:100%;overflow-x:hidden;}
  body{background:var(--bg);color:var(--ink);
       font-family:'Segoe UI',system-ui,-apple-system,'Helvetica Neue',sans-serif;
       font-size:14px;line-height:1.4;}

  .head{background:var(--blue);color:#fff;padding:14px clamp(14px,2.2vw,30px) 12px;
        display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;}
  .head h1{margin:0;font-size:clamp(15px,1.4vw,19px);font-weight:600;letter-spacing:.2px;}
  .head .sub{font-size:11.5px;opacity:.82;margin-top:3px;}
  .head .tag{font-size:11.5px;background:rgba(255,255,255,.16);padding:6px 12px;
             border-radius:4px;white-space:nowrap;}

  /* ---------- key insights ---------- */
  .insights{padding:14px clamp(14px,2.2vw,30px) 2px;}
  .ins-head{display:flex;align-items:baseline;gap:10px;margin-bottom:9px;flex-wrap:wrap;}
  .ins-head h2{margin:0;font-size:12.5px;font-weight:700;text-transform:uppercase;
               letter-spacing:.9px;color:var(--blue);}
  .ins-head span{font-size:11px;color:var(--muted);}
  .ins-grid{display:grid;gap:clamp(8px,.9vw,12px);grid-template-columns:repeat(auto-fit,minmax(238px,1fr));}
  .ins{background:#fff;border:1px solid var(--line);border-left:3px solid var(--orange);
       border-radius:7px;padding:11px 13px;box-shadow:0 1px 2px rgba(27,39,51,.05);}
  .ins .t{font-size:10px;letter-spacing:.6px;text-transform:uppercase;color:var(--muted);
          font-weight:700;margin-bottom:5px;}
  .ins .b{font-size:12.5px;line-height:1.5;color:var(--ink);}
  .ins .b b{font-weight:700;}
  .ins .num{font-weight:700;color:var(--blue);}
  .ins .bad{color:var(--red);font-weight:700;}
  .ins .good{color:var(--green);font-weight:700;}
  .ins.risk{border-left-color:var(--red);}
  .ins.win{border-left-color:var(--green);}

  /* ---------- slicers ---------- */
  .slicers{display:flex;gap:9px;padding:11px clamp(14px,2.2vw,30px);background:#fff;
           border-top:1px solid var(--line);border-bottom:1px solid var(--line);
           align-items:center;flex-wrap:wrap;position:sticky;top:0;z-index:40;margin-top:12px;}
  .sl{position:relative;}
  .sl-btn{display:flex;align-items:center;gap:8px;background:#F4F6F9;border:1px solid var(--line);
          border-radius:5px;padding:7px 11px;font-size:12px;cursor:pointer;color:var(--ink);
          font-family:inherit;min-width:118px;justify-content:space-between;}
  .sl-btn:hover{border-color:var(--blue2);}
  .sl-btn.on{background:#EAF1F8;border-color:var(--blue);}
  .sl-l{color:var(--muted);font-size:10.5px;text-transform:uppercase;letter-spacing:.5px;
        display:block;line-height:1.1;}
  .sl-v{font-weight:600;font-size:12px;display:block;line-height:1.3;}
  .caret{color:var(--muted);font-size:9px;}
  .sl-menu{display:none;position:absolute;top:calc(100% + 5px);left:0;min-width:210px;
           background:#fff;border:1px solid var(--line);border-radius:6px;
           box-shadow:0 8px 22px rgba(27,39,51,.16);padding:6px;z-index:50;max-height:330px;
           overflow-y:auto;}
  .sl-menu.open{display:block;}
  .sl-opt{display:flex;align-items:center;gap:8px;padding:6px 8px;border-radius:4px;
          font-size:12px;cursor:pointer;user-select:none;}
  .sl-opt:hover{background:#F4F6F9;}
  .sl-opt input{accent-color:var(--blue);cursor:pointer;margin:0;}
  .sl-opt.all{border-bottom:1px solid var(--line);border-radius:4px 4px 0 0;
              margin-bottom:4px;font-weight:600;}
  .reset{margin-left:auto;font-size:12px;color:var(--blue);font-weight:600;cursor:pointer;
         background:none;border:none;font-family:inherit;padding:6px 4px;}
  .reset:hover{text-decoration:underline;}

  /* ---------- KPI ---------- */
  .kpis{display:grid;gap:clamp(9px,1vw,14px);padding:clamp(12px,1.6vw,18px) clamp(14px,2.2vw,30px) 4px;
        grid-template-columns:repeat(auto-fit,minmax(150px,1fr));}
  .kpi{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px;
       border-left:3px solid var(--blue);box-shadow:0 1px 2px rgba(27,39,51,.05);}
  .kpi-l{font-size:10px;color:var(--muted);letter-spacing:.7px;font-weight:600;
         text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  .kpi-v{font-size:clamp(18px,1.6vw,23px);font-weight:700;margin:6px 0 2px;letter-spacing:-.4px;}
  .kpi-s{font-size:10.5px;color:var(--muted);}
  .kpi.warn{border-left-color:var(--orange);}

  /* ---------- charts ---------- */
  .grid{display:grid;gap:clamp(9px,1vw,14px);padding:4px clamp(14px,2.2vw,30px) clamp(14px,2vw,24px);
        grid-template-columns:repeat(12,minmax(0,1fr));}
  .card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:11px 13px 9px;
        box-shadow:0 1px 2px rgba(27,39,51,.05);min-width:0;overflow:hidden;}
  .card h3{margin:0 0 2px;font-size:12.5px;font-weight:600;color:var(--ink);}
  .card .note{font-size:10px;color:var(--muted);margin:0 0 4px;min-height:13px;}
  .card svg{display:block;width:100%;height:auto;}
  .s8{grid-column:span 8;} .s4{grid-column:span 4;} .s6{grid-column:span 6;}
  .sub{font-size:10px;color:var(--muted);margin:8px 0 2px;font-weight:600;letter-spacing:.3px;}
  .pill{display:inline-block;font-size:9px;padding:1px 5px;border-radius:3px;
        background:#FFF3E6;color:#9A5B18;border:1px solid #F3D9BE;margin-left:4px;
        vertical-align:middle;font-weight:600;}
  .foot{padding:0 clamp(14px,2.2vw,30px) 26px;font-size:11px;color:var(--muted);line-height:1.75;}
  .foot b{color:var(--ink);}
  .foot .prov{background:#FFF8EC;border:1px solid #F3D9BE;border-radius:6px;padding:9px 11px;
              margin-bottom:10px;color:#6B4E1B;font-size:11px;line-height:1.7;}
  @media (max-width:1180px){ .s8{grid-column:span 12;} .s4{grid-column:span 6;} .s6{grid-column:span 6;} }
  @media (max-width:820px){ .s4,.s6{grid-column:span 12;} .sl-btn{min-width:100px;} }
  .empty{padding:22px 0;text-align:center;color:var(--muted);font-size:12px;}
</style>
</head><body>

<div class="head">
  <div>
    <h1>E-Commerce Sales &amp; Customer Dashboard</h1>
    <div class="sub" id="sub">Indian e-commerce · 2023-01-01 → 2025-12-31 · realised revenue basis</div>
  </div>
  <div class="tag" id="chip">—</div>
</div>

<div class="insights">
  <div class="ins-head">
    <h2>Key insights</h2>
    <span>full dataset, 2023–2025 — not affected by the filters below</span>
  </div>
  <div class="ins-grid" id="insights"></div>
</div>

<div class="slicers" id="slicers">
  <div class="sl" data-k="y"></div><div class="sl" data-k="m"></div><div class="sl" data-k="c"></div>
  <div class="sl" data-k="r"></div><div class="sl" data-k="s"></div>
  <button class="reset" id="reset">↺ Reset filters</button>
</div>

<div class="kpis" id="kpis"></div>

<div class="grid">
  <div class="card s8"><h3>Monthly revenue</h3>
    <p class="note">₹ Cr · realised orders</p><div id="v-monthly"></div>
    <p class="sub">GROSS MARGIN %</p><div id="v-margin"></div></div>
  <div class="card s4"><h3>Customer segment</h3>
    <p class="note">share of sales</p><div id="v-segment"></div></div>

  <div class="card s4"><h3>Sales by category</h3>
    <p class="note">₹ Cr</p><div id="v-cat-sales"></div></div>
  <div class="card s4"><h3>Profit by category</h3>
    <p class="note">₹ Cr · same 10 categories</p><div id="v-cat-profit"></div></div>
  <div class="card s4"><h3>Sales by region</h3>
    <p class="note">₹ Cr</p><div id="v-region"></div></div>

  <div class="card s6"><h3>Top 10 products<span class="pill" id="pill-prod"></span></h3>
    <p class="note">by sales, ₹ Cr</p><div id="v-products"></div></div>
  <div class="card s6"><h3>Payment method<span class="pill" id="pill-pay"></span></h3>
    <p class="note">share of sales</p><div id="v-payment"></div></div>
</div>

<div class="foot">
  <div class="prov">
    <b>Data provenance.</b> This is a <b>synthetic (programmatically generated) dataset</b> — the
    “Indian E-Commerce Customer &amp; Order Intelligence” set, generated with a documented Python script
    (seed 42). Customer names, product names, brands and campaign names are fabricated; no real person,
    company or transaction is represented. It is released CC0. Figures here are therefore illustrative of
    method, <i>not</i> of any real market.
  </div>
  <b>Revenue definition.</b> Revenue is <b>Delivered + Returned</b> orders at item level (excludes
  shipping and tax). Returned orders are included because the sale happened and returns are tracked
  separately — the return-rate KPI above shows the exposure, and the net-of-returns figure is given
  alongside it.<br>
  <b>Slicers.</b> Multi-select. Charts marked <span class="pill">Month ignored</span> aggregate at a
  coarser grain for payload size.<br>
  <b>Source.</b> 254,331 order lines · 100,000 orders · 15 states · 22 categories · 550 products.
</div>

<script>
const D = __DATA__, F_ = D.facts;
const F = {y:new Set(), m:new Set(), c:new Set(), r:new Set(), s:new Set()};
const MN = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const SLICERS = [
  {k:'y', label:'Year',     opts:D.years.map((v,i)=>[i,String(v)])},
  {k:'m', label:'Month',    opts:D.months.map(v=>[v-1,MN[v-1]])},
  {k:'c', label:'Category', opts:D.cats.map((v,i)=>[i,v])},
  {k:'r', label:'Region',   opts:D.regs.map((v,i)=>[i,v])},
  {k:'s', label:'Segment',  opts:D.segs.map((v,i)=>[i,v])},
];
const pass=(set,v)=>set.size===0||set.has(v);
const CR=v=>(v/1e7).toLocaleString('en-IN',{maximumFractionDigits:1,minimumFractionDigits:1});
const INT=v=>Math.round(v).toLocaleString('en-IN');
const PCT=v=>(v*100).toFixed(1)+'%';
const cr=v=>'₹'+CR(v)+' Cr';

/* ---------------- key insights (static, full dataset) ---------------- */
function renderInsights(){
  const f=F_, items=[
    {t:'Margin is the story, not revenue', cls:'risk',
     b:`Electronics is <span class="num">${(f.elec_rev/f.rev*100).toFixed(0)}% of sales</span>
        (${cr(f.elec_rev)}) but earns only <span class="bad">${cr(f.elec_prof)}</span> —
        <b>${f.elec_mg.toFixed(2)}% margin</b>. Fashion earns <span class="good">${cr(f.fash_prof)}</span>
        on ${cr(f.fash_rev)} — <b>${f.fash_mg.toFixed(0)}%</b>.`},
    {t:'Growth came from volume, not basket size', cls:'',
     b:`2023 ${cr(f.rv2023)} → 2024 ${cr(f.rv2024)} (flat) → 2025 <b>${cr(f.rv2025)}</b>,
        <span class="good">+${f.yoy25.toFixed(0)}%</span>. Orders <b>+${f.ord_growth.toFixed(0)}%</b> while
        AOV moved ${((f.aov25/f.aov23-1)*100).toFixed(1)}% — every rupee of growth is more orders.`},
    {t:'One SKU is a fifth of the company', cls:'risk',
     b:`A single smartwatch = <span class="num">${f.sku_share.toFixed(1)}% of revenue</span>
        (${cr(f.sku_rev)}) but just <b>${f.sku_profit_share.toFixed(1)}% of profit</b>
        (${f.sku_mg.toFixed(2)}% margin). <b>Concentration risk, not a data error</b> — see README §6.2.`},
    {t:'Demand is concentrated in three regions', cls:'',
     b:`South, North and West are <span class="num">${f.top3_share.toFixed(0)}% of sales</span>;
        East and Central together only ${(100-f.top3_share).toFixed(0)}%. Growth spend outside the big three
        has little proof behind it yet.`},
    {t:'Returns are 5.3% — and they count as revenue', cls:'win',
     b:`Item return rate <b>${f.return_rate.toFixed(1)}%</b>. Excluding returned orders, revenue is
        ${cr(f.rev_ex_returns)} rather than ${cr(f.rev)} — a
        <span class="num">${cr(f.returned_rev)}</span> exposure the headline does not show.`},
  ];
  document.getElementById('insights').innerHTML = items.map(i=>
    `<div class="ins ${i.cls}"><div class="t">${i.t}</div><div class="b">${i.b}</div></div>`).join('');
}

/* ---------------- slicers ---------------- */
function buildSlicers(){
  document.querySelectorAll('.sl').forEach(el=>{
    const k=el.dataset.k, cfg=SLICERS.find(s=>s.k===k);
    el.innerHTML=`<button class="sl-btn" data-open="${k}">
        <span><span class="sl-l">${cfg.label}</span><span class="sl-v" id="lbl-${k}">All</span></span>
        <span class="caret">▾</span></button>
      <div class="sl-menu" id="menu-${k}">
        <label class="sl-opt all"><input type="checkbox" data-all="${k}" checked> All ${cfg.label.toLowerCase()}s</label>
        ${cfg.opts.map(([v,t])=>`<label class="sl-opt"><input type="checkbox" data-k="${k}" value="${v}"> ${t}</label>`).join('')}
      </div>`;
  });
  document.querySelectorAll('[data-open]').forEach(btn=>{
    btn.onclick=e=>{e.stopPropagation();
      const m=document.getElementById('menu-'+btn.dataset.open), was=m.classList.contains('open');
      document.querySelectorAll('.sl-menu').forEach(x=>x.classList.remove('open'));
      if(!was) m.classList.add('open');};
  });
  document.querySelectorAll('[data-all]').forEach(cb=>{
    cb.onchange=()=>{const k=cb.dataset.all; F[k].clear();
      document.querySelectorAll(`#menu-${k} input[data-k]`).forEach(i=>i.checked=false);
      sync(k); renderAll();};
  });
  document.querySelectorAll('input[data-k]').forEach(cb=>{
    cb.onchange=()=>{const k=cb.dataset.k,v=Number(cb.value);
      cb.checked?F[k].add(v):F[k].delete(v);
      if(F[k].size) document.querySelector(`[data-all="${k}"]`).checked=false;
      sync(k); renderAll();};
  });
  document.getElementById('reset').onclick=()=>{
    Object.keys(F).forEach(k=>F[k].clear());
    document.querySelectorAll('.sl-menu input').forEach(i=>i.checked=i.hasAttribute('data-all'));
    SLICERS.forEach(s=>sync(s.k)); renderAll();};
  SLICERS.forEach(s=>sync(s.k));
}
function sync(k){
  const cfg=SLICERS.find(s=>s.k===k), set=F[k];
  const lbl=document.getElementById('lbl-'+k), btn=document.querySelector(`[data-open="${k}"]`);
  if(set.size===0){lbl.textContent='All';btn.classList.remove('on');}
  else if(set.size===1){lbl.textContent=cfg.opts.find(o=>o[0]===[...set][0])[1];btn.classList.add('on');}
  else {lbl.textContent=set.size+' selected';btn.classList.add('on');}
}
document.addEventListener('click',()=>document.querySelectorAll('.sl-menu').forEach(m=>m.classList.remove('open')));

/* ---------------- aggregation ---------------- */
function aggregate(){
  let rev=0,prof=0,units=0,lines=0,rets=0,delivRev=0;
  const custs=new Set(), ords=new Set();
  const byMonth=new Map(), profMonth=new Map(), lineMonth=new Map(), retMonth=new Map(),
        delivMonth=new Map(), byCatRev=new Map(), byCatProf=new Map(), byReg=new Map(), bySeg=new Map();
  for(const row of D.main){
    if(!pass(F.y,row[0])||!pass(F.m,row[1])||!pass(F.c,row[2])||!pass(F.r,row[3])||!pass(F.s,row[4])) continue;
    rev+=row[5]; prof+=row[6]; units+=row[7]; lines+=row[8]; rets+=row[9];
    for(const ci of row[10]) custs.add(ci);
    for(const oi of row[11]) ords.add(oi);
    const mk=row[0]*12+row[1];
    byMonth.set(mk,(byMonth.get(mk)||0)+row[5]);
    profMonth.set(mk,(profMonth.get(mk)||0)+row[6]);
    lineMonth.set(mk,(lineMonth.get(mk)||0)+row[8]);
    retMonth.set(mk,(retMonth.get(mk)||0)+row[9]);
    byCatRev.set(row[2],(byCatRev.get(row[2])||0)+row[5]);
    byCatProf.set(row[2],(byCatProf.get(row[2])||0)+row[6]);
    byReg.set(row[3],(byReg.get(row[3])||0)+row[5]);
    bySeg.set(row[4],(bySeg.get(row[4])||0)+row[5]);
  }
  const prodMap=new Map();
  for(const row of D.prodCube){
    if(!pass(F.y,row[0])||!pass(F.r,row[1])||!pass(F.s,row[2])) continue;
    if(!pass(F.c,D.prods[row[3]][1])) continue;
    prodMap.set(row[3],(prodMap.get(row[3])||0)+row[4]);
  }
  const payMap=new Map();
  for(const row of D.payCube){
    if(!pass(F.y,row[0])||!pass(F.c,row[1])||!pass(F.r,row[2])||!pass(F.s,row[3])) continue;
    payMap.set(row[4],(payMap.get(row[4])||0)+row[5]);
  }
  return {rev,prof,units,lines,rets,customers:custs.size,orders:ords.size,
          byMonth,profMonth,lineMonth,retMonth,
          byCatRev,byCatProf,byReg,bySeg,
          topProducts:[...prodMap.entries()].sort((a,b)=>b[1]-a[1]).slice(0,10),
          payItems:D.pays.map((n,i)=>({label:n,value:payMap.get(i)||0})).filter(x=>x.value>0)
                          .sort((a,b)=>b.value-a.value)};
}

/* ---------------- chart primitives ---------------- */
const NS='http://www.w3.org/2000/svg';
const el=(t,a)=>{const e=document.createElementNS(NS,t);for(const k in a)e.setAttribute(k,a[k]);return e;};
function root(host,w,h){host.innerHTML='';
  const s=el('svg',{viewBox:`0 0 ${w} ${h}`,preserveAspectRatio:'xMidYMid meet'});
  s.style.display='block';s.style.width='100%';s.style.height='auto';host.appendChild(s);return s;}
function emptyMsg(host,m){host.innerHTML=`<div class="empty">${m}</div>`;}
function niceMax(v){if(v<=0)return 1;const p=Math.pow(10,Math.floor(Math.log10(v))),n=v/p;
  const m=n<=1?1:n<=1.2?1.2:n<=1.5?1.5:n<=2?2:n<=2.5?2.5:n<=3?3:n<=4?4:n<=5?5:n<=10?10:10;return m*p;}

function hBar(host,items,{fmt=v=>INT(v),colorFn=()=>'#2E5A88',maxBars=10,w=560,rowH=26,labelChars=26}={}){
  if(!items.length) return emptyMsg(host,'No data for this filter');
  items=items.slice(0,maxBars);
  const h=items.length*rowH+16,padL=Math.min(250,labelChars*6.2),padR=58;
  const s=root(host,w,h),max=niceMax(Math.max(...items.map(i=>Math.abs(i.value)))),plotW=w-padL-padR;
  items.forEach((it,i)=>{
    const y=i*rowH+8,bw=Math.max(1,Math.abs(it.value)/max*plotW);
    const lbl=it.label.length>labelChars?it.label.slice(0,labelChars-1)+'…':it.label;
    const t=el('text',{x:padL-8,y:y+rowH/2+3.5,'text-anchor':'end','font-size':'10.5',fill:'#5B6B7C'});
    t.textContent=lbl;
    if(it.title){const ti=el('title',{});ti.textContent=it.title;t.appendChild(ti);}
    s.appendChild(t);
    s.appendChild(el('rect',{x:padL,y:y+3,width:bw,height:rowH-9,rx:2,fill:colorFn(it)}));
    const v=el('text',{x:padL+bw+6,y:y+rowH/2+3.5,'font-size':'10',fill:'#5B6B7C'});
    v.textContent=fmt(it.value);s.appendChild(v);
  });
}
function vBar(host,items,{fmt=v=>INT(v),color='#2E5A88',w=430,h=230}={}){
  if(!items.length||items.every(i=>i.value===0)) return emptyMsg(host,'No data for this filter');
  const padL=44,padR=10,padT=12,padB=30,s=root(host,w,h);
  const max=niceMax(Math.max(...items.map(i=>i.value))),plotW=w-padL-padR,plotH=h-padT-padB,bw=plotW/items.length;
  [0,.5,1].forEach(f=>{const y=padT+plotH*(1-f);
    s.appendChild(el('line',{x1:padL,x2:w-padR,y1:y,y2:y,stroke:'#EEF1F5','stroke-width':1}));
    const t=el('text',{x:padL-6,y:y+3.5,'text-anchor':'end','font-size':'9',fill:'#8A97A6'});
    t.textContent=Math.round(max*f).toLocaleString('en-IN');s.appendChild(t);});
  items.forEach((it,i)=>{const bh=plotH*(it.value/max),x=padL+i*bw+bw*0.22,y=padT+plotH-bh;
    s.appendChild(el('rect',{x,y,width:bw*0.56,height:Math.max(1,bh),rx:2,fill:it.color||color}));
    const v=el('text',{x:x+bw*0.28,y:y-4,'text-anchor':'middle','font-size':'9.5',fill:'#5B6B7C'});
    v.textContent=fmt(it.value);s.appendChild(v);
    const t=el('text',{x:x+bw*0.28,y:h-10,'text-anchor':'middle','font-size':'9.5',fill:'#5B6B7C'});
    t.textContent=it.label;s.appendChild(t);});
}
/* single-axis line: no dual axis, ever */
function lineChart(host,series,{w=760,h=230,fmt=v=>v.toFixed(0),band=null,padB=26}={}){
  const vals=series[0].data.map(p=>p.y);
  if(!vals.length||Math.max(...vals)===0) return emptyMsg(host,'No data for this filter');
  const padL=52,padR=14,padT=12,s=root(host,w,h);
  const plotW=w-padL-padR,plotH=h-padT-padB,n=vals.length;
  const max=niceMax(Math.max(...vals)),min=band&&band[0]<0?band[0]:0;
  const X=i=>padL+(n<=1?plotW/2:i*(plotW/(n-1)));
  const Y=v=>padT+plotH-((v-min)/(max-min))*plotH;
  [0,.5,1].forEach(f=>{const y=padT+plotH*(1-f);
    s.appendChild(el('line',{x1:padL,x2:w-padR,y1:y,y2:y,stroke:f===0?'#D8DEE6':'#EEF1F5','stroke-width':1}));
    const t=el('text',{x:padL-7,y:y+3.5,'text-anchor':'end','font-size':'9',fill:'#8A97A6'});
    t.textContent=fmt(min+(max-min)*f);s.appendChild(t);});
  if(band){const y=Y(band[1]);
    s.appendChild(el('line',{x1:padL,x2:w-padR,y1:y,y2:y,stroke:'#B5495B','stroke-width':1,'stroke-dasharray':'4 3'}));
    const t=el('text',{x:w-padR-2,y:y-4,'text-anchor':'end','font-size':'8.5',fill:'#B5495B'});
    t.textContent='company avg '+band[1].toFixed(1)+'%';s.appendChild(t);}
  const sr=series[0],pts=sr.data.map((p,i)=>`${X(i).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
  if(sr.fill) s.appendChild(el('polygon',{points:`${padL},${Y(min)} ${pts} ${X(n-1)},${Y(min)}`,fill:sr.color,opacity:.12}));
  s.appendChild(el('polyline',{points:pts,fill:'none',stroke:sr.color,'stroke-width':2.2,'stroke-linejoin':'round'}));
  const step=Math.max(1,Math.ceil(n/9));
  series[0].data.forEach((p,i)=>{ if(i%step!==0&&i!==n-1) return;
    const last=i===n-1, anch=last?'end':(i===0?'start':'middle');
    const t=el('text',{x:X(i)+(last?2:(i===0?-2:0)),y:h-8,'text-anchor':anch,
                       'font-size':'9',fill:'#8A97A6'});
    t.textContent=p.x;s.appendChild(t);});
}
function donut(host,items,{w=300,h=230,center='',sub=''}={}){
  const total=items.reduce((a,b)=>a+b.value,0);
  if(!total) return emptyMsg(host,'No data for this filter');
  const s=root(host,w,h),cx=w*0.36,cy=h/2,R=Math.min(h*0.40,w*0.28),r=R*0.58;
  const COLS=['#2E5A88','#5D8CB8','#E8833A','#9DB4CC','#B5495B','#4B9B6B'];
  let a0=-Math.PI/2;
  items.forEach((it,i)=>{const a1=a0+(it.value/total)*Math.PI*2,large=(a1-a0)>Math.PI?1:0;
    s.appendChild(el('path',{d:[`M ${cx+R*Math.cos(a0)} ${cy+R*Math.sin(a0)}`,
      `A ${R} ${R} 0 ${large} 1 ${cx+R*Math.cos(a1)} ${cy+R*Math.sin(a1)}`,
      `L ${cx+r*Math.cos(a1)} ${cy+r*Math.sin(a1)}`,
      `A ${r} ${r} 0 ${large} 0 ${cx+r*Math.cos(a0)} ${cy+r*Math.sin(a0)}`,'Z'].join(' '),
      fill:COLS[i%COLS.length],stroke:'#fff','stroke-width':2}));a0=a1;});
  const c1=el('text',{x:cx,y:cy+2,'text-anchor':'middle','font-size':'14','font-weight':'700',fill:'#1B2733'});
  c1.textContent=center;s.appendChild(c1);
  const c2=el('text',{x:cx,y:cy+17,'text-anchor':'middle','font-size':'9',fill:'#5B6B7C'});
  c2.textContent=sub;s.appendChild(c2);
  let ly=26;
  items.forEach((it,i)=>{s.appendChild(el('rect',{x:w*0.66,y:ly-8,width:9,height:9,rx:2,fill:COLS[i%COLS.length]}));
    const t=el('text',{x:w*0.66+14,y:ly,'font-size':'10',fill:'#5B6B7C'});
    t.textContent=`${it.label}  ${(it.value/total*100).toFixed(1)}%`;s.appendChild(t);ly+=19;});
}

/* ---------------- views ---------------- */
function renderKPIs(a){
  const rr = a.lines ? a.rets/a.lines*100 : 0;
  const cards=[
    ['Total sales', cr(a.rev), 'realised, item level', ''],
    ['Gross profit', cr(a.prof), 'merchandise only', ''],
    ['Margin', a.rev?(a.prof/a.rev*100).toFixed(2)+'%':'—', 'blended', ''],
    ['Return rate', rr.toFixed(1)+'%', a.lines?INT(a.rets)+' of '+INT(a.lines)+' lines':'—', 'warn'],
    ['Total orders', INT(a.orders), 'delivered + returned', ''],
    ['Buying customers', INT(a.customers), 'distinct in filter', ''],
    ['Avg order value', '₹'+INT(a.rev/Math.max(a.orders,1)), 'per order', ''],
    ['Units sold', INT(a.units), 'line quantity', ''],
  ];
  document.getElementById('kpis').innerHTML=cards.map(([l,v,s,c])=>
    `<div class="kpi ${c}"><div class="kpi-l">${l}</div><div class="kpi-v">${v}</div>
     <div class="kpi-s">${s}</div></div>`).join('');
}
function renderCharts(a){
  const keys=[...a.byMonth.keys()].sort((x,y)=>x-y);
  const xlab=k=>`${MN[k%12]} ${Math.floor(k/12)+2023}`;
  lineChart(document.getElementById('v-monthly'),
    [{name:'Revenue',color:'#2E5A88',fill:true,
      data:keys.map(k=>({x:xlab(k),y:a.byMonth.get(k)/1e7}))}],
    {fmt:v=>v.toFixed(0),w:760,h:210});
  /* margin % on its OWN axis — previously a dual axis made an 8% line look identical to revenue */
  lineChart(document.getElementById('v-margin'),
    [{name:'Gross margin %',color:'#B5495B',
      data:keys.map(k=>{const rv=a.byMonth.get(k)||0;
        return {x:xlab(k), y: rv ? (a.profMonth.get(k)||0)/rv*100 : null};})
        .filter(p=>p.y!==null)}],
    {fmt:v=>v.toFixed(0)+'%',w:760,h:120,padB:20});

  donut(document.getElementById('v-segment'),
    D.segs.map((s,i)=>({label:s,value:a.bySeg.get(i)||0})).filter(x=>x.value>0).sort((x,y)=>y.value-x.value),
    {center:'₹'+CR(a.rev)+'Cr',sub:'realised'});

  const catItems=D.cats.map((c,i)=>({idx:i,label:c,value:a.byCatRev.get(i)||0}))
                       .filter(x=>x.value>0).sort((x,y)=>y.value-x.value).slice(0,10);
  hBar(document.getElementById('v-cat-sales'),catItems,{fmt:v=>CR(v),maxBars:10,w:430,rowH:24,labelChars:17});
  hBar(document.getElementById('v-cat-profit'),
       catItems.map(it=>({label:it.label,value:a.byCatProf.get(it.idx)||0})).sort((x,y)=>y.value-x.value),
       {fmt:v=>CR(v),maxBars:10,w:430,rowH:24,labelChars:17,colorFn:it=>it.value<0?'#B5495B':'#4B9B6B'});
  vBar(document.getElementById('v-region'),
       D.regs.map((r,i)=>({label:r,value:(a.byReg.get(i)||0)/1e7})).sort((x,y)=>y.value-x.value),
       {fmt:v=>CR(v*1e7),w:430,h:230});
  hBar(document.getElementById('v-products'),
       a.topProducts.map(([pi,v])=>({label:D.prods[pi][0],value:v,title:D.prods[pi][0]})),
       {fmt:v=>CR(v),maxBars:10,w:680,rowH:26,labelChars:42,colorFn:()=>'#E8833A'});
  const payTotal=a.payItems.reduce((x,y)=>x+y.value,0);
  let payItems=a.payItems.slice(0,7); const rest=a.payItems.slice(7);
  if(rest.length) payItems=payItems.concat([{label:`Other (${rest.length})`,
      value:rest.reduce((x,y)=>x+y.value,0),other:true}]);
  hBar(document.getElementById('v-payment'),payItems,
       {fmt:v=>PCT(v/payTotal),maxBars:8,w:600,rowH:26,labelChars:22,
        colorFn:it=>it.other?'#9DB4CC':'#5D8CB8'});
  const monthOn=F.m.size>0;
  document.getElementById('pill-prod').textContent=monthOn?'Month ignored':'';
  document.getElementById('pill-pay').textContent=monthOn?'Month ignored':'';
}
function renderAll(){
  const a=aggregate(); renderKPIs(a); renderCharts(a);
  const nf=Object.values(F).reduce((n,s)=>n+s.size,0);
  document.getElementById('sub').textContent =
    'Synthetic · Indian e-commerce · 2023-01-01 → 2025-12-31 · realised revenue basis'
    + (nf?` · ${nf} filter${nf>1?'s':''} active`:'');
  document.getElementById('chip').textContent =
    `${cr(a.rev)} · ${INT(a.orders)} orders · ${INT(a.customers)} customers`;
}
renderInsights();
buildSlicers();
renderAll();
</script>
</body></html>"""

out = PROJ / "dashboard" / "ecommerce_dashboard.html"
out.write_text(HTML.replace("__DATA__", payload), encoding="utf-8")
print(f"wrote {out} ({out.stat().st_size/1024/1024:.2f} MB)")
