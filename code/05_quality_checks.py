#!/usr/bin/env python3
"""Stage 5: Quality checks and final Stata output generation.

Validates the full pipeline, generates logs, and produces final
output in .dta format.
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = ROOT / "data_raw"
DATA_INT = ROOT / "data_intermediate"
DATA_FINAL = ROOT / "data_final"
LOGS = ROOT / "logs"
DATA_FINAL.mkdir(parents=True, exist_ok=True)

# ── Load all data ──────────────────────────────────────────────────
preprocessed = pd.read_excel(DATA_INT / "01_bunkering_preprocessed.xlsx")
tx_base = pd.read_excel(DATA_INT / "02_transaction_level_base.xlsx")
tx_final = pd.read_stata(DATA_INT / "04_transaction_with_weather.dta")

# Stata stores missing strings as empty strings; convert back to NaN
for col in tx_final.columns:
    if tx_final[col].dtype == object:
        tx_final[col] = tx_final[col].replace("", np.nan)

def coverage_counts(df, col, expected):
    s = df[col]
    return {
        "full": int((s == expected).sum()),
        "partial": int(((s > 0) & (s < expected)).sum()),
        "none": int((s == 0).sum()),
        "missing": int(s.isna().sum()),
    }


def date_key(value):
    if pd.isna(value):
        return None
    parsed = pd.to_datetime(value, errors="coerce")
    if pd.isna(parsed):
        return str(value)
    return parsed.strftime("%Y-%m-%d")


print("=" * 60)
print("STAGE 5: QUALITY CHECKS & FINAL OUTPUT")
print("=" * 60)

# ═══════════════════════════════════════════════════════════════════
# Check 1: Transaction counts
# ═══════════════════════════════════════════════════════════════════
raw_tx_count = preprocessed["transaction_id"].nunique()
final_tx_count = len(tx_final)
dup_count = preprocessed["is_duplicate"].sum()
non_dup_rows = len(preprocessed[preprocessed["is_duplicate"] == 0])

print(f"\n--- Check 1: Transaction Counts ---")
print(f"  Raw transaction count: {raw_tx_count}")
print(f"  Duplicate rows removed: {dup_count}")
print(f"  Non-duplicate rows: {non_dup_rows}")
print(f"  Final transaction count: {final_tx_count}")
print(f"  Transactions lost: {raw_tx_count - final_tx_count}")

# ═══════════════════════════════════════════════════════════════════
# Check 2: STS counts
# ═══════════════════════════════════════════════════════════════════
raw_sts_rows = preprocessed[preprocessed["is_sts"] == 1]
raw_sts_count = len(raw_sts_rows[raw_sts_rows["is_duplicate"] == 0])
final_sts_slots = tx_final["supplier_n"].sum()

print(f"\n--- Check 2: STS Counts ---")
print(f"  Raw STS rows (non-duplicate): {raw_sts_count}")
print(f"  Final STS slots (sum of supplier_n): {int(final_sts_slots)}")
print(f"  STS count match: {'PASS' if raw_sts_count == final_sts_slots else 'FAIL'}")

# ═══════════════════════════════════════════════════════════════════
# Check 3: supplier_n = STS row count per transaction
# ═══════════════════════════════════════════════════════════════════
non_dup_sts = raw_sts_rows[raw_sts_rows["is_duplicate"] == 0]
raw_sts_per_tx = non_dup_sts.groupby("transaction_id").size()
final_supplier_n = tx_final.set_index("transaction_id")["supplier_n"]

# Compare
common_ids = raw_sts_per_tx.index.intersection(final_supplier_n.index)
mismatch_count = (raw_sts_per_tx.loc[common_ids] != final_supplier_n.loc[common_ids]).sum()

print(f"\n--- Check 3: supplier_n vs STS rows ---")
print(f"  Transactions with STS in both: {len(common_ids)}")
print(f"  Mismatches: {mismatch_count}")
print(f"  supplier_n match: {'PASS' if mismatch_count == 0 else 'FAIL'}")

if mismatch_count > 0:
    mismatches = pd.DataFrame({
        "raw_sts_count": raw_sts_per_tx.loc[common_ids],
        "final_supplier_n": final_supplier_n.loc[common_ids],
    })
    mismatched = mismatches[
        mismatches["raw_sts_count"] != mismatches["final_supplier_n"]
    ]
    print(f"  Mismatched transactions: {len(mismatched)}")
    mismatched.to_excel(LOGS / "supplier_n_mismatches.xlsx")
else:
    stale_supplier_log = LOGS / "supplier_n_mismatches.xlsx"
    if stale_supplier_log.exists():
        stale_supplier_log.unlink()

# ═══════════════════════════════════════════════════════════════════
# Check 4: duration_STS = sum of all duration_STSk
# ═══════════════════════════════════════════════════════════════════
duration_cols = [c for c in tx_final.columns
                 if c.startswith("duration_STS") and c != "duration_STS"
                 and c != "duration_STS_final"]
tx_final["duration_STS_check"] = tx_final[duration_cols].sum(axis=1)
mismatch_dur = abs(tx_final["duration_STS"] - tx_final["duration_STS_check"]) > 0.01
n_mismatch_dur = mismatch_dur.sum()

print(f"\n--- Check 4: duration_STS integrity ---")
print(f"  Mismatches: {n_mismatch_dur}")
print(f"  duration_STS match: {'PASS' if n_mismatch_dur == 0 else 'FAIL'}")

# ═══════════════════════════════════════════════════════════════════
# Check 5: end_STS_final = last STS end date
# ═══════════════════════════════════════════════════════════════════
max_sts = max([int(c.split("_STS")[-1]) for c in tx_final.columns
               if c.startswith("end_STS") and c != "end_STS_final"] + [0])

end_sts_mismatches = []
for _, row in tx_final[tx_final["supplier_n"] > 0].iterrows():
    k = int(row["supplier_n"])
    expected_date = date_key(row.get(f"end_STS{k}"))
    actual_date = date_key(row.get("end_STS_final"))
    expected_hour = row.get(f"endhour_STS{k}")
    actual_hour = row.get("endhour_STS_final")
    if expected_date != actual_date or expected_hour != actual_hour:
        end_sts_mismatches.append({
            "transaction_id": row["transaction_id"],
            "supplier_n": k,
            "expected_end_STS_final": expected_date,
            "actual_end_STS_final": actual_date,
            "expected_endhour_STS_final": expected_hour,
            "actual_endhour_STS_final": actual_hour,
        })

end_sts_mismatch_count = len(end_sts_mismatches)
print(f"\n--- Check 5: end_STS_final integrity ---")
print(f"  max_STS: {max_sts}")
print(f"  Mismatches: {end_sts_mismatch_count}")
print(f"  end_STS_final match: {'PASS' if end_sts_mismatch_count == 0 else 'FAIL'}")
if end_sts_mismatches:
    pd.DataFrame(end_sts_mismatches).to_excel(
        LOGS / "end_sts_final_mismatches.xlsx", index=False
    )
else:
    stale_end_log = LOGS / "end_sts_final_mismatches.xlsx"
    if stale_end_log.exists():
        stale_end_log.unlink()

# ═══════════════════════════════════════════════════════════════════
# Check 6: Port matching
# ═══════════════════════════════════════════════════════════════════
ports_with_data = tx_final["port"].notna().sum()
ports_missing = tx_final["port"].isna().sum()
ports_multi = tx_final["port_multi_flag"].sum()

print(f"\n--- Check 6: Port Matching ---")
print(f"  Transactions with port: {ports_with_data}")
print(f"  Transactions without port: {ports_missing}")
print(f"  Multi-port transactions: {ports_multi}")
print(f"  Port match rate: {ports_with_data / len(tx_final) * 100:.1f}%")

# Check that all ports come from the port table
VALID_PORTS = {"秀山东", "马峙", "条帚门", "虾峙门", "衢山"}
all_ports = set(tx_final["port"].dropna().unique())
invalid_ports = all_ports - VALID_PORTS
print(f"  Valid ports: {all_ports & VALID_PORTS}")
print(f"  Invalid ports: {invalid_ports if invalid_ports else 'None'}")
print(f"  Port validation: {'PASS' if not invalid_ports else 'FAIL'}")

# ═══════════════════════════════════════════════════════════════════
# Check 7: Anchor matching
# ═══════════════════════════════════════════════════════════════════
anchor_match_rate = tx_final["anchor_match_flag"].mean() * 100
# Only for transactions with port
tx_with_port = tx_final[tx_final["port"].notna()]
anchor_match_rate_port = tx_with_port["anchor_match_flag"].mean() * 100

print(f"\n--- Check 7: Anchor Matching ---")
print(f"  Anchor match rate (all): {anchor_match_rate:.1f}%")
print(f"  Anchor match rate (with port): {anchor_match_rate_port:.1f}%")
print(f"  openhour_6 range: {tx_final['openhour_6'].min():.0f} - {tx_final['openhour_6'].max():.0f}")
print(f"  openhour_12 range: {tx_final['openhour_12'].min():.0f} - {tx_final['openhour_12'].max():.0f}")
print(f"  openhour_24 range: {tx_final['openhour_24'].min():.0f} - {tx_final['openhour_24'].max():.0f}")

# ═══════════════════════════════════════════════════════════════════
# Check 8: Weather matching
# ═══════════════════════════════════════════════════════════════════
weather_match_rate = tx_final["weather_match_flag"].mean() * 100

print(f"\n--- Check 8: Weather Matching ---")
print(f"  Weather match rate (all): {weather_match_rate:.1f}%")
print(f"  weather_match (with port): {tx_with_port['weather_match_flag'].mean() * 100:.1f}%")
print(f"  v1 openhourf_6 range: {tx_final['openhourf_6_v1'].min():.0f} - {tx_final['openhourf_6_v1'].max():.0f}")
print(f"  v1 openhourf_12 range: {tx_final['openhourf_12_v1'].min():.0f} - {tx_final['openhourf_12_v1'].max():.0f}")
print(f"  v1 openhourf_24 range: {tx_final['openhourf_24_v1'].min():.0f} - {tx_final['openhourf_24_v1'].max():.0f}")

# ═══════════════════════════════════════════════════════════════════
# Check 8b: Window coverage
# ═══════════════════════════════════════════════════════════════════
expected_coverage = {6: 13, 12: 25, 24: 49}
anchor_coverage = {
    w: coverage_counts(tx_final, f"anchor_window_coverage_{w}", expected)
    for w, expected in expected_coverage.items()
}
weather_coverage = {
    w: coverage_counts(tx_final, f"weather_window_coverage_{w}", expected)
    for w, expected in expected_coverage.items()
}

print(f"\n--- Check 8b: Window Coverage ---")
for w in [6, 12, 24]:
    ac = anchor_coverage[w]
    wc = weather_coverage[w]
    print(
        f"  Anchor {w}h coverage: full={ac['full']}, "
        f"partial={ac['partial']}, none={ac['none']}, missing={ac['missing']}"
    )
    print(
        f"  Weather {w}h coverage: full={wc['full']}, "
        f"partial={wc['partial']}, none={wc['none']}, missing={wc['missing']}"
    )

# ═══════════════════════════════════════════════════════════════════
# Check 9: Same supplier multi-STS
# ═══════════════════════════════════════════════════════════════════
supplier_cols = [c for c in tx_final.columns
                 if c.startswith("supplier") and c != "supplier_n"
                 and c[8:].isdigit()]

same_sup_ids = []
for _, row in tx_final.iterrows():
    suppliers = [row[c] for c in supplier_cols if pd.notna(row[c])]
    if len(suppliers) > len(set(suppliers)):
        same_sup_ids.append(row["transaction_id"])

print(f"\n--- Check 9: Same Supplier Multi-STS ---")
print(f"  Transactions with same supplier multiple STS: {len(same_sup_ids)}")
if same_sup_ids:
    same_sup_log = tx_final[tx_final["transaction_id"].isin(same_sup_ids)][
        ["transaction_id", "supplier_n"] + supplier_cols
    ]
    same_sup_log.to_excel(LOGS / "same_supplier_multi_sts_cases.xlsx", index=False)

# ═══════════════════════════════════════════════════════════════════
# Check 10: Cross-day rounding
# ═══════════════════════════════════════════════════════════════════
cross_day_log = LOGS / "time_rounding_cross_day_cases.xlsx"
if cross_day_log.exists():
    cross_day = pd.read_excel(cross_day_log)
    print(f"\n--- Check 10: Cross-Day Rounding ---")
    print(f"  Cross-day rounding cases: {len(cross_day)}")

# ═══════════════════════════════════════════════════════════════════
# Check 11: Unmatched ports
# ═══════════════════════════════════════════════════════════════════
unmatched_port_log = LOGS / "unmatched_ports.xlsx"
if unmatched_port_log.exists():
    unmatched = pd.read_excel(unmatched_port_log)
    print(f"\n--- Check 11: Unmatched Ports ---")
    print(f"  Unique unmatched location strings: {len(unmatched)}")

# ═══════════════════════════════════════════════════════════════════
# Create final output
# ═══════════════════════════════════════════════════════════════════

# Drop check column
if "duration_STS_check" in tx_final.columns:
    tx_final = tx_final.drop(columns=["duration_STS_check"])

# Convert date columns to strings for Stata compatibility
date_cols = ["startdate", "enddate"] + \
            [c for c in tx_final.columns
             if (c.startswith("start_STS") or c.startswith("end_STS"))
             and not c.startswith("end_STS_final")]

for col in date_cols:
    if col in tx_final.columns:
        tx_final[col] = tx_final[col].astype(str)

# Save final Stata output
tx_final.to_stata(DATA_FINAL / "bunkering_transaction_final.dta",
                  write_index=False, version=118)

print(f"\n=== Final Outputs ===")
print(f"  {DATA_FINAL / 'bunkering_transaction_final.dta'}")
print(f"  Transactions: {len(tx_final)}")
print(f"  Variables: {len(tx_final.columns)}")

# ═══════════════════════════════════════════════════════════════════
# Processing Summary
# ═══════════════════════════════════════════════════════════════════
summary = f"""# Processing Summary — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Data Volume
- Raw rows: {len(preprocessed)}
- Raw transactions: {raw_tx_count}
- Duplicate rows removed: {dup_count}
- Final transactions: {final_tx_count}
- Raw STS rows (non-dup): {raw_sts_count}
- Final STS slots: {int(final_sts_slots)}

## STS Expansion
- max_STS: {max_sts}
- supplier_n = STS record count: {'PASS' if mismatch_count == 0 else 'FAIL'}
- duration_STS = sum(duration_STSk): {'PASS' if n_mismatch_dur == 0 else 'FAIL'}
- end_STS_final = last STS endpoint: {'PASS' if end_sts_mismatch_count == 0 else 'FAIL'}
- Same-supplier multi-STS cases: {len(same_sup_ids)}

## Port Matching
- Port match rate: {ports_with_data / len(tx_final) * 100:.1f}%
- Multi-port transactions: {ports_multi}
- All ports from valid table: {'PASS' if not invalid_ports else 'FAIL'}

## Anchor Open Matching
- Match rate (all transactions): {anchor_match_rate:.1f}%
- Match rate (transactions with port): {anchor_match_rate_port:.1f}%
- openhour_6 mean: {tx_final['openhour_6'].mean():.1f}
- openhour_12 mean: {tx_final['openhour_12'].mean():.1f}
- openhour_24 mean: {tx_final['openhour_24'].mean():.1f}

## Weather Forecast Matching
- Match rate (all transactions): {weather_match_rate:.1f}%
- match rate (with port): {tx_with_port['weather_match_flag'].mean() * 100:.1f}%
- v1 openhourf_6 mean: {tx_final['openhourf_6_v1'].mean():.1f}
- v1 openhourf_12 mean: {tx_final['openhourf_12_v1'].mean():.1f}
- v1 openhourf_24 mean: {tx_final['openhourf_24_v1'].mean():.1f}
- v2 openhourf_6 mean: {tx_final['openhourf_6_v2'].mean():.1f}
- v2 openhourf_12 mean: {tx_final['openhourf_12_v2'].mean():.1f}
- v2 openhourf_24 mean: {tx_final['openhourf_24_v2'].mean():.1f}

## Window Coverage
- Anchor 6h: full={anchor_coverage[6]['full']}, partial={anchor_coverage[6]['partial']}, no coverage={anchor_coverage[6]['none']}
- Anchor 12h: full={anchor_coverage[12]['full']}, partial={anchor_coverage[12]['partial']}, no coverage={anchor_coverage[12]['none']}
- Anchor 24h: full={anchor_coverage[24]['full']}, partial={anchor_coverage[24]['partial']}, no coverage={anchor_coverage[24]['none']}
- Weather 6h: full={weather_coverage[6]['full']}, partial={weather_coverage[6]['partial']}, no coverage={weather_coverage[6]['none']}
- Weather 12h: full={weather_coverage[12]['full']}, partial={weather_coverage[12]['partial']}, no coverage={weather_coverage[12]['none']}
- Weather 24h: full={weather_coverage[24]['full']}, partial={weather_coverage[24]['partial']}, no coverage={weather_coverage[24]['none']}

## Closure Frequency Source
- closure_frequency.csv: Average closure frequencies
- v2 uses Average open probability = 1 - Average closure_frequency

## Log Files
- unmatched_ports.xlsx
- multi_port_transactions.xlsx
- duplicate_records.xlsx
- multi_sts_cases.xlsx
- same_supplier_multi_sts_cases.xlsx
- time_rounding_cross_day_cases.xlsx
"""

summary_path = LOGS / "processing_summary.md"
summary_path.write_text(summary)
print(f"\n  Summary: {summary_path}")

print(f"\n{'=' * 60}")
print("STAGE 5 COMPLETE")
print(f"{'=' * 60}")
