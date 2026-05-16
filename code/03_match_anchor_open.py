#!/usr/bin/env python3
"""Stage 3: Match anchor open data to transaction-level data.

For each transaction, compute openhour_6, openhour_12, openhour_24
based on the anchor open status around the transaction start time.
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = ROOT / "data_raw"
DATA_INT = ROOT / "data_intermediate"

# ── Load data ─────────────────────────────────────────────────────
tx = pd.read_excel(DATA_INT / "02_transaction_level_base.xlsx")
# Convert empty string ports to NaN
tx["port"] = tx["port"].replace("", np.nan)
print(f"Loaded {len(tx)} transactions")

anchor = pd.read_stata(DATA_RAW / "锚地开放.dta")
print(f"Loaded {len(anchor)} anchor records")

# ── Prepare anchor data ───────────────────────────────────────────
anchor["open_flag"] = (anchor["status"].str.lower() == "open").astype(int)
anchor["anchor_dt"] = pd.to_datetime(
    anchor["date_numeric"].astype(str) + " " + anchor["hour"].astype(str) + ":00:00"
)

# Build lookup: port -> sorted list of (datetime, open_flag)
anchor_lookup = {}
for port, grp in anchor.groupby("port"):
    grp_sorted = grp.sort_values("anchor_dt")
    anchor_lookup[port] = (
        grp_sorted["anchor_dt"].values,
        grp_sorted["open_flag"].values,
    )

# ── Compute window open hours for each transaction ────────────────
def compute_windows(port, start_dt):
    """Return (openhour_6, openhour_12, openhour_24, cov_6, cov_12, cov_24, matched)."""
    if port not in anchor_lookup:
        return np.nan, np.nan, np.nan, 0, 0, 0, 0

    dts, flags = anchor_lookup[port]
    t_start = np.datetime64(start_dt)

    results = {}
    for w in [6, 12, 24]:
        t_min = t_start - np.timedelta64(w, "h")
        t_max = t_start + np.timedelta64(w, "h")

        mask = (dts >= t_min) & (dts <= t_max)
        total = mask.sum()
        open_hours = flags[mask].sum()

        results[f"openhour_{w}"] = open_hours
        results[f"cov_{w}"] = total

    return (results["openhour_6"], results["openhour_12"], results["openhour_24"],
            results["cov_6"], results["cov_12"], results["cov_24"], 1)


# Apply per transaction
tx["start_dt"] = pd.to_datetime(
    tx["startdate"].astype(str) + " " + tx["starthour"].astype(int).astype(str) + ":00:00"
)

window_results = tx.apply(
    lambda r: compute_windows(r["port"], r["start_dt"])
    if pd.notna(r["port"]) else (np.nan, np.nan, np.nan, 0, 0, 0, 0),
    axis=1,
)

tx["openhour_6"] = window_results.apply(lambda x: x[0])
tx["openhour_12"] = window_results.apply(lambda x: x[1])
tx["openhour_24"] = window_results.apply(lambda x: x[2])
tx["anchor_window_coverage_6"] = window_results.apply(lambda x: x[3])
tx["anchor_window_coverage_12"] = window_results.apply(lambda x: x[4])
tx["anchor_window_coverage_24"] = window_results.apply(lambda x: x[5])
tx["anchor_match_flag"] = window_results.apply(lambda x: x[6])
tx["anchor_match_flag"] = tx["anchor_match_flag"].fillna(0).astype(int)

# Clean up
tx = tx.drop(columns=["start_dt"])

# ── Save ───────────────────────────────────────────────────────────
tx.to_stata(DATA_INT / "03_transaction_with_anchor.dta", write_index=False, version=118)
print(f"Saved to 03_transaction_with_anchor.dta")

# Summary
matched = tx[tx["anchor_match_flag"] == 1]
print(f"\n=== Stage 3 Summary ===")
print(f"Transactions with port: {tx['port'].notna().sum()}")
print(f"Anchor matched: {tx['anchor_match_flag'].sum()}")
print(f"Anchor unmatched: {(tx['anchor_match_flag'] == 0).sum()}")
print(f"\nopenhour_6: mean={matched['openhour_6'].mean():.1f}, "
      f"min={matched['openhour_6'].min():.0f}, max={matched['openhour_6'].max():.0f}")
print(f"openhour_12: mean={matched['openhour_12'].mean():.1f}, "
      f"min={matched['openhour_12'].min():.0f}, max={matched['openhour_12'].max():.0f}")
print(f"openhour_24: mean={matched['openhour_24'].mean():.1f}, "
      f"min={matched['openhour_24'].min():.0f}, max={matched['openhour_24'].max():.0f}")
print(f"\nWindow coverage:")
print(f"  cov_6: mean={matched['anchor_window_coverage_6'].mean():.1f}/13")
print(f"  cov_12: mean={matched['anchor_window_coverage_12'].mean():.1f}/25")
print(f"  cov_24: mean={matched['anchor_window_coverage_24'].mean():.1f}/49")
