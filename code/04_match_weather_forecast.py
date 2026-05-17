#!/usr/bin/env python3
"""Stage 4: Match weather forecast data to transaction-level data.

For each transaction, compute:
- v1: openhourf_6_v1, openhourf_12_v1, openhourf_24_v1
      (index 2,3,4 → open; index 1 → closed)
- v2: openhourf_6_v2, openhourf_12_v2, openhourf_24_v2
      (using closure frequency for open probability)
"""

import pandas as pd
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = ROOT / "data_raw"
DATA_INT = ROOT / "data_intermediate"

# ── Load data ─────────────────────────────────────────────────────
tx = pd.read_stata(DATA_INT / "03_transaction_with_anchor.dta")
print(f"Loaded {len(tx)} transactions")

weather = pd.read_stata(DATA_RAW / "气象预报.dta")
print(f"Loaded {len(weather)} weather records")

# ── Prepare weather data ──────────────────────────────────────────
weather["weather_dt"] = pd.to_datetime(
    weather["date_numeric"].astype(str) + " " + weather["hour"].astype(str) + ":00:00"
)

# Build lookup: port → sorted array of (datetime, weather_index)
weather_lookup = {}
for port, grp in weather.groupby("port"):
    grp_sorted = grp.sort_values("weather_dt")
    weather_lookup[port] = (
        grp_sorted["weather_dt"].values,
        grp_sorted["气象指数"].values.astype(int),
    )

# ═══════════════════════════════════════════════════════════════════
# Version 1: binary open/closed based on index
#   index 1 → closed (0), index 2,3,4 → open (1)
# ═══════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════
# Version 2: open probability using closure frequency from CSV
# ═══════════════════════════════════════════════════════════════════

# Parse closure frequency CSV
cf_raw = pd.read_csv(DATA_RAW / "closure_frequency.csv",
                      skiprows=[0, 1, 6],
                      names=["MIO", "Tiaozhoumen", "Xiushan East", "Xiazhimen", "Qushan", "Mazhi", "Average"])

# Map CSV English column names to Chinese port names
CSV_TO_PORT = {
    "Tiaozhoumen": "条帚门",
    "Xiushan East": "秀山东",
    "Xiazhimen": "虾峙门",
    "Qushan": "衢山",
    "Mazhi": "马峙",
}

# Build port_closure_freq[port][index] = closure_frequency (0-1)
CLOSURE_FREQ = {}
for csv_col, port_name in CSV_TO_PORT.items():
    row_map = {}
    for _, row in cf_raw.iterrows():
        idx = int(row["MIO"])
        freq_str = str(row[csv_col]).replace("%", "")
        row_map[idx] = float(freq_str) / 100.0
    CLOSURE_FREQ[port_name] = row_map

print(f"Loaded closure frequency for ports: {list(CLOSURE_FREQ.keys())}")

# ═══════════════════════════════════════════════════════════════════
# Precompute: for each unique port+datetime in transactions, find the
# weather index, then compute window sums
# ═══════════════════════════════════════════════════════════════════

tx["start_dt"] = pd.to_datetime(
    tx["startdate"].astype(str) + " " + tx["starthour"].astype(int).astype(str) + ":00:00"
)


def compute_weather_windows(port, start_dt):
    """Return (v1_6, v1_12, v1_24, v2_6, v2_12, v2_24, cov_6, cov_12, cov_24, matched)."""
    if port not in weather_lookup:
        return (np.nan,)*9 + (0,)

    dts, indices = weather_lookup[port]
    t_start = np.datetime64(start_dt)

    # Get port-specific closure frequency
    cf = CLOSURE_FREQ.get(port, {})

    results = {}
    for w in [6, 12, 24]:
        t_min = t_start - np.timedelta64(w, "h")
        t_max = t_start + np.timedelta64(w, "h")

        mask = (dts >= t_min) & (dts <= t_max)
        matched_indices = indices[mask]
        total = len(matched_indices)

        # v1: binary open/closed
        v1_open = np.sum(matched_indices >= 2)

        # v2: open probability sum using port-specific closure frequency
        v2_open = sum(1 - cf.get(idx, 0) for idx in matched_indices)

        results[f"v1_{w}"] = v1_open
        results[f"v2_{w}"] = round(v2_open, 1)
        results[f"cov_{w}"] = total

    return (results["v1_6"], results["v1_12"], results["v1_24"],
            results["v2_6"], results["v2_12"], results["v2_24"],
            results["cov_6"], results["cov_12"], results["cov_24"], 1)


weather_results = tx.apply(
    lambda r: compute_weather_windows(r["port"], r["start_dt"])
    if pd.notna(r["port"]) else (np.nan,)*9 + (0,),
    axis=1,
)

tx["openhourf_6_v1"] = weather_results.apply(lambda x: x[0])
tx["openhourf_12_v1"] = weather_results.apply(lambda x: x[1])
tx["openhourf_24_v1"] = weather_results.apply(lambda x: x[2])
tx["openhourf_6_v2"] = weather_results.apply(lambda x: x[3])
tx["openhourf_12_v2"] = weather_results.apply(lambda x: x[4])
tx["openhourf_24_v2"] = weather_results.apply(lambda x: x[5])
tx["weather_window_coverage_6"] = weather_results.apply(lambda x: x[6])
tx["weather_window_coverage_12"] = weather_results.apply(lambda x: x[7])
tx["weather_window_coverage_24"] = weather_results.apply(lambda x: x[8])
tx["weather_match_flag"] = weather_results.apply(lambda x: x[9])
tx["weather_match_flag"] = tx["weather_match_flag"].fillna(0).astype(int)

# Clean up
tx = tx.drop(columns=["start_dt"])

# ── Save ───────────────────────────────────────────────────────────
tx.to_stata(DATA_INT / "04_transaction_with_weather.dta", write_index=False, version=118)
print(f"Saved to 04_transaction_with_weather.dta")

# Summary
matched = tx[tx["weather_match_flag"] == 1]
print(f"\n=== Stage 4 Summary ===")
print(f"Transactions with port: {tx['port'].notna().sum()}")
print(f"Weather matched: {tx['weather_match_flag'].sum()}")
print(f"Weather unmatched: {(tx['weather_match_flag'] == 0).sum()}")

print(f"\nVersion 1 (binary open/closed):")
print(f"  openhourf_6_v1:  mean={matched['openhourf_6_v1'].mean():.1f}")
print(f"  openhourf_12_v1: mean={matched['openhourf_12_v1'].mean():.1f}")
print(f"  openhourf_24_v1: mean={matched['openhourf_24_v1'].mean():.1f}")

print(f"\nVersion 2 (open probability, port-specific closure freq):")
print(f"  openhourf_6_v2:  mean={matched['openhourf_6_v2'].mean():.1f}")
print(f"  openhourf_12_v2: mean={matched['openhourf_12_v2'].mean():.1f}")
print(f"  openhourf_24_v2: mean={matched['openhourf_24_v2'].mean():.1f}")

print(f"\nWindow coverage:")
print(f"  cov_6: mean={matched['weather_window_coverage_6'].mean():.1f}/13")
print(f"  cov_12: mean={matched['weather_window_coverage_12'].mean():.1f}/25")
print(f"  cov_24: mean={matched['weather_window_coverage_24'].mean():.1f}/49")

print(f"\nClosure frequency source: closure_frequency.csv (port-specific, Nov 2022 – Jul 2024)")
