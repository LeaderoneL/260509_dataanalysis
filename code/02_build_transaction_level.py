#!/usr/bin/env python3
"""Stage 2: Build transaction-level data from preprocessed row-level data.

Key principles:
- One row per transaction
- Each STS-bunkering record → one STS slot (NOT aggregated by supplier)
- supplier_n = number of STS records (not unique suppliers)
- max_STS = max STS count across all transactions
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime

# ── Paths ──────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
DATA_INT = ROOT / "data_intermediate"
LOGS = ROOT / "logs"
DATA_INT.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)

# ── Load preprocessed data ─────────────────────────────────────────
df = pd.read_excel(DATA_INT / "01_bunkering_preprocessed.xlsx")
print(f"Loaded {len(df)} rows, {df['transaction_id'].nunique()} transactions")

# Remove duplicates
df_clean = df[df["is_duplicate"] == 0].copy()
print(f"After removing duplicates: {len(df_clean)} rows, "
      f"{df_clean['transaction_id'].nunique()} transactions")

# ── Parse rounded datetimes ────────────────────────────────────────
df_clean["start_dt_round"] = pd.to_datetime(df_clean["start_dt_round"])
df_clean["end_dt_round"] = pd.to_datetime(df_clean["end_dt_round"])

# ═══════════════════════════════════════════════════════════════════
# Build transaction-level aggregates
# ═══════════════════════════════════════════════════════════════════

# --- Transaction time boundaries ---
tx_time = df_clean.groupby("transaction_id").agg(
    tx_start_dt=("start_dt_round", "min"),
    tx_end_dt=("end_dt_round", "max"),
).reset_index()

tx_time["startdate"] = tx_time["tx_start_dt"].dt.date
tx_time["starthour"] = tx_time["tx_start_dt"].dt.hour
tx_time["enddate"] = tx_time["tx_end_dt"].dt.date
tx_time["endhour"] = tx_time["tx_end_dt"].dt.hour
tx_time["duration"] = (
    (tx_time["tx_end_dt"] - tx_time["tx_start_dt"]).dt.total_seconds() / 3600
).round(0).astype(int)

# --- Vessel info (first non-null per transaction) ---
vessel_cols = ["vessel_name", "vessel_code", "vessel_type",
               "in_service_commission", "dwt", "gt", "draught"]
vessel_info = df_clean.groupby("transaction_id")[vessel_cols].first().reset_index()

# --- Port identification ---
def resolve_port(grp):
    """Resolve port for a transaction from anchorage rows."""
    anch_rows = grp[grp["is_anchorage"] == 1]
    if len(anch_rows) == 0:
        return pd.Series({"port": None, "port_multi_flag": 0,
                          "port_all_matched": None, "unmatched_port": None})

    matched = anch_rows["port_matched"].dropna().unique()
    unmatched_raw = anch_rows.loc[
        anch_rows["port_matched"].isna(), "port_raw"
    ].dropna().unique()

    if len(matched) == 0:
        return pd.Series({"port": None, "port_multi_flag": 0,
                          "port_all_matched": None,
                          "unmatched_port": "; ".join(unmatched_raw)
                          if len(unmatched_raw) > 0 else None})

    if len(matched) == 1:
        return pd.Series({"port": matched[0], "port_multi_flag": 0,
                          "port_all_matched": matched[0],
                          "unmatched_port": "; ".join(unmatched_raw)
                          if len(unmatched_raw) > 0 else None})

    # Multiple matched ports
    return pd.Series({"port": matched[0], "port_multi_flag": 1,
                      "port_all_matched": "; ".join(matched),
                      "unmatched_port": "; ".join(unmatched_raw)
                      if len(unmatched_raw) > 0 else None})


port_info = df_clean.groupby("transaction_id").apply(resolve_port).reset_index()

# ═══════════════════════════════════════════════════════════════════
# STS expansion
# ═══════════════════════════════════════════════════════════════════

sts_rows = df_clean[df_clean["is_sts"] == 1].copy()
sts_rows = sts_rows.sort_values(["transaction_id", "start_dt_round"])

# Assign STS sequence number within each transaction
sts_rows["sts_seq"] = sts_rows.groupby("transaction_id").cumcount() + 1

# Determine max_STS
max_sts = sts_rows.groupby("transaction_id").size().max()
print(f"max_STS = {max_sts}")

# Pivot STS data: each seq becomes a set of columns
sts_pivoted = sts_rows.pivot_table(
    index="transaction_id",
    columns="sts_seq",
    values=["supplier_raw", "start_dt_round", "end_dt_round"],
    aggfunc="first"
)

# Build expanded STS columns
sts_expanded = {}
for k in range(1, max_sts + 1):
    if k in sts_pivoted["supplier_raw"].columns:
        sts_expanded[f"supplier{k}"] = sts_pivoted["supplier_raw"][k]
        sts_expanded[f"start_STS{k}"] = sts_pivoted["start_dt_round"][k].dt.date
        sts_expanded[f"starthour_STS{k}"] = sts_pivoted["start_dt_round"][k].dt.hour
        sts_expanded[f"end_STS{k}"] = sts_pivoted["end_dt_round"][k].dt.date
        sts_expanded[f"endhour_STS{k}"] = sts_pivoted["end_dt_round"][k].dt.hour
        # duration_STS{k} in hours
        sts_expanded[f"duration_STS{k}"] = (
            (sts_pivoted["end_dt_round"][k] - sts_pivoted["start_dt_round"][k])
            .dt.total_seconds() / 3600
        ).round(1)
    else:
        sts_expanded[f"supplier{k}"] = None
        sts_expanded[f"start_STS{k}"] = None
        sts_expanded[f"starthour_STS{k}"] = np.nan
        sts_expanded[f"end_STS{k}"] = None
        sts_expanded[f"endhour_STS{k}"] = np.nan
        sts_expanded[f"duration_STS{k}"] = np.nan

sts_expanded_df = pd.DataFrame(sts_expanded, index=sts_pivoted.index)
sts_expanded_df = sts_expanded_df.reset_index()

# --- Supplier count ---
supplier_n = sts_rows.groupby("transaction_id").size().reset_index(name="supplier_n")

# --- Duration_STS (sum of all STS durations) ---
duration_cols = [f"duration_STS{k}" for k in range(1, max_sts + 1)]
sts_expanded_df["duration_STS"] = sts_expanded_df[duration_cols].sum(axis=1)

# --- End STS final ---
# Get the last STS end time per transaction
last_sts = sts_rows.groupby("transaction_id")["end_dt_round"].max().reset_index()
last_sts.columns = ["transaction_id", "end_STS_final_dt"]
last_sts["end_STS_final"] = last_sts["end_STS_final_dt"].dt.date
last_sts["endhour_STS_final"] = last_sts["end_STS_final_dt"].dt.hour

# ═══════════════════════════════════════════════════════════════════
# Assemble final dataset
# ═══════════════════════════════════════════════════════════════════

final = vessel_info.merge(tx_time, on="transaction_id", how="left")
final = final.merge(port_info, on="transaction_id", how="left")
final = final.merge(supplier_n, on="transaction_id", how="left")
final = final.merge(sts_expanded_df, on="transaction_id", how="left")
final = final.merge(
    last_sts[["transaction_id", "end_STS_final", "endhour_STS_final"]],
    on="transaction_id", how="left"
)

# Fill supplier_n for transactions with no STS
final["supplier_n"] = final["supplier_n"].fillna(0).astype(int)

# ═══════════════════════════════════════════════════════════════════
# Logs
# ═══════════════════════════════════════════════════════════════════

# Multi-port transactions
multi_port = final[final["port_multi_flag"] == 1][
    ["transaction_id", "port", "port_all_matched", "unmatched_port"]
]
if len(multi_port) > 0:
    multi_port.to_excel(LOGS / "multi_port_transactions.xlsx", index=False)
    print(f"Multi-port transactions logged: {len(multi_port)}")

# Multi-STS cases (transactions with >1 STS)
multi_sts = final[final["supplier_n"] > 1][
    ["transaction_id", "supplier_n"] +
    [c for c in final.columns if c.startswith("supplier") and c != "supplier_n"]
]
if len(multi_sts) > 0:
    multi_sts.to_excel(LOGS / "multi_sts_cases.xlsx", index=False)
    print(f"Multi-STS transactions logged: {len(multi_sts)}")

# Same supplier multi-STS cases
if max_sts > 1:
    supplier_cols = [f"supplier{k}" for k in range(1, max_sts + 1)]
    sts_check = final[["transaction_id"] + supplier_cols].copy()
    # Find where any two supplier columns have same non-null value
    same_supplier_rows = []
    for _, row in sts_check.iterrows():
        suppliers = [row[f"supplier{k}"] for k in range(1, max_sts + 1)
                     if pd.notna(row[f"supplier{k}"])]
        if len(suppliers) > len(set(suppliers)):
            same_supplier_rows.append(row["transaction_id"])
    if same_supplier_rows:
        same_sup_log = final[final["transaction_id"].isin(same_supplier_rows)][
            ["transaction_id", "supplier_n"] + supplier_cols
        ]
        same_sup_log.to_excel(LOGS / "same_supplier_multi_sts_cases.xlsx", index=False)
        print(f"Same-supplier multi-STS cases logged: {len(same_sup_log)}")

# ═══════════════════════════════════════════════════════════════════
# Define output column order
# ═══════════════════════════════════════════════════════════════════

base_cols = [
    "transaction_id",
    "vessel_name", "vessel_code", "vessel_type",
    "in_service_commission", "dwt", "gt", "draught",
    "startdate", "starthour", "enddate", "endhour", "duration",
    "port", "port_multi_flag", "port_all_matched", "unmatched_port",
]

sts_cols = []
for k in range(1, max_sts + 1):
    sts_cols += [
        f"supplier{k}",
        f"start_STS{k}", f"starthour_STS{k}",
        f"end_STS{k}", f"endhour_STS{k}",
        f"duration_STS{k}",
    ]

summary_cols = [
    "supplier_n", "duration_STS",
    "end_STS_final", "endhour_STS_final",
]

output_cols = base_cols + sts_cols + summary_cols
final = final[output_cols]

# ── Save ───────────────────────────────────────────────────────────
output_path = DATA_INT / "02_transaction_level_base.xlsx"
final.to_excel(output_path, index=False)
print(f"\nStage 2 complete. Output: {output_path}")
print(f"Transactions: {len(final)}")
print(f"max_STS: {max_sts}")
print(f"Transactions with STS: {(final['supplier_n'] > 0).sum()}")
print(f"Transactions without STS: {(final['supplier_n'] == 0).sum()}")
print(f"Total STS slots: {final['supplier_n'].sum()}")
print(f"Ports matched: {final['port'].notna().sum()}")
print(f"Multi-port: {final['port_multi_flag'].sum()}")
