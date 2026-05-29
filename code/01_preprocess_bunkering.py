#!/usr/bin/env python3
"""Stage 1: Row-level preprocessing of raw Bunkering Record v3 data.

Reads the raw Excel, parses vessel info, times, draught, supplier,
matches ports via fuzzy matching, and outputs a preprocessed row-level file.
"""

import re
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
DATA_RAW = ROOT / "data_raw"
DATA_INT = ROOT / "data_intermediate"
LOGS = ROOT / "logs"
DATA_INT.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)

# ── Port mapping table ─────────────────────────────────────────────
# Standard port name → list of accepted prefixes (lowercased, spaceless for matching)
PORT_MAP = {
    "秀山东": [
        "zhoushantideandberthwaitinganchorage",
        "zhoushantideandberth",
        "zhoushantideand",
        "zhoushaneastanchorage",
        "zhoushaneastanch",
        "zhoushaneastancho",
    ],
    "马峙": [
        "zhoushanmashino1anchorage",
        "zhoushanmashino2anchorage",
        "zhoushanmashidangerousgoodsanchorage",
        "zhoushanmashino1",
        "zhoushanmashino2",
        "zhoushanmazhidangerousgoodsanchorage",
        "zhoushanmazhidan",
        "zhoushanmazhidanger",
        "zhoushanmazhidangero",
        "zhoushanmazhidangerou",
        "zhoushanmashino",
    ],
    "条帚门": [
        "zhoushanxiazhimensouthanchorage",
        "zhoushanxiazhimensou",
        "zhoushanxiazhimensout",
        "zhoushanxiazhimenso",
        "zhoushanxiazhimesouth",
        "zhoushanxiazhimens",
    ],
    "虾峙门": [
        "zhoushanxiazhimennorthanchorage",
        "zhoushanxiazhimennor",
        "zhoushanxiazhimennort",
        "zhoushanxiazhimenno",
        "zhoushannorthanchorage",
        "zhoushannorthanch",
        "zhoushannorthanc",
        "zhoushannorthanchorag",
    ],
    "衢山": [
        "zhoushanqushanbunkeringanchorage",
        "zhoushanqushanbunkeringanchorage1&2",
        "zhoushanqushanbunk",
        "zhoushanqushanbunke",
        "zhoushanqushanbunker",
        "zhoushanqushanbunkeri",
        "zhoushanqushanbunkerin",
        "zhoushanqushanancho",
        "zhoushanqushananchor",
        "zhoushanqushanbun",
    ],
}


def normalize_for_matching(s):
    """Lowercase, remove spaces and non-breaking spaces, strip."""
    if pd.isna(s):
        return ""
    s = str(s)
    s = s.replace("\xa0", "").replace(" ", "").lower()
    return s


def match_port(location_detail):
    """Match a raw location detail string to a standard Chinese port name.
    Returns (port_name, matched_raw) or (None, None).
    """
    if pd.isna(location_detail):
        return None, None

    raw = str(location_detail).strip()
    # Only anchorage rows start with "At "
    if not raw.lower().startswith("at "):
        return None, None

    norm = normalize_for_matching(raw)
    # Remove "At" prefix for matching
    if norm.startswith("at"):
        norm = norm[2:]

    for port_name, prefixes in PORT_MAP.items():
        for prefix in prefixes:
            if norm.startswith(prefix):
                return port_name, raw

    return None, raw


# ── Read raw Excel ─────────────────────────────────────────────────
raw = pd.read_excel(DATA_RAW / "Bunkering Record v3.xlsx", header=None)
print(f"Raw shape: {raw.shape}")

# Drop metadata/header rows
raw = raw.drop([0, 1]).reset_index(drop=True)
raw.columns = [
    "vessel_raw", "col_1", "operation", "location",
    "country", "start_raw", "end_raw", "duration_raw",
    "draught_raw", "location_details",
]
print(f"Data rows after dropping header: {raw.shape[0]}")

# ── Generate row_id ────────────────────────────────────────────────
raw["row_id"] = range(len(raw))

# ── Fix "TS - Bunkering" typo ──────────────────────────────────────
raw["operation"] = raw["operation"].replace("TS - Bunkering", "STS - Bunkering")

# ── Identify transaction boundaries ────────────────────────────────
raw["is_new_transaction"] = raw["vessel_raw"].notna()
raw["transaction_id"] = raw["is_new_transaction"].cumsum()

# ── Forward-fill vessel info ───────────────────────────────────────
raw["vessel_raw"] = raw.groupby("transaction_id")["vessel_raw"].transform(
    lambda x: x.ffill()
)

# ── Parse vessel info ──────────────────────────────────────────────
vessel_pattern = re.compile(
    r"^(.+?)\s*\((\d+)\)\s*[-–—]\s*(.+?),\s*(In Service/Commission|In Casualty or Repairing|Laid-Up|To Be Broken Up|Broken Up)"
    r"(?:,\s*(\d+(?:,\d{3})*(?:\.\d+)?)\s*dwt)?"
    r"(?:,\s*(\d+(?:,\d{3})*(?:\.\d+)?)\s*gt)?"
)


def parse_vessel(text):
    if pd.isna(text):
        return pd.Series({"vessel_name": None, "vessel_code": None,
                          "vessel_type": None, "in_service_commission": None,
                          "dwt": np.nan, "gt": np.nan})
    text = str(text).strip()
    m = vessel_pattern.match(text)
    if m:
        name = m.group(1).strip()
        code = m.group(2).strip()
        vtype = m.group(3).strip()
        status = m.group(4).strip()

        dwt_val = np.nan
        if m.group(5):
            dwt_val = float(m.group(5).replace(",", ""))

        gt_val = np.nan
        if m.group(6):
            gt_val = float(m.group(6).replace(",", ""))

        return pd.Series({"vessel_name": name, "vessel_code": code,
                          "vessel_type": vtype, "in_service_commission": status,
                          "dwt": dwt_val, "gt": gt_val})
    else:
        # Fallback: try to extract what we can
        return pd.Series({"vessel_name": text, "vessel_code": None,
                          "vessel_type": None, "in_service_commission": None,
                          "dwt": np.nan, "gt": np.nan})


vessel_parsed = raw["vessel_raw"].apply(parse_vessel)
raw = pd.concat([raw, vessel_parsed], axis=1)

# ── Parse time fields ──────────────────────────────────────────────
def parse_dt(val):
    """Parse datetime from two possible formats."""
    if pd.isna(val):
        return pd.NaT
    val = str(val).strip()
    # Format 1: "2023-01-30 04:15:00"
    try:
        return pd.to_datetime(val, format="%Y-%m-%d %H:%M:%S")
    except (ValueError, TypeError):
        pass
    # Format 2: "02 Feb 2023 08:11"
    try:
        return pd.to_datetime(val, format="%d %b %Y %H:%M")
    except (ValueError, TypeError):
        pass
    # Format 3: "14 Apr 2026 08:03" (no leading zero on day)
    try:
        return pd.to_datetime(val, format="%d %b %Y %H:%M")
    except (ValueError, TypeError):
        pass
    return pd.NaT


raw["start_dt"] = raw["start_raw"].apply(parse_dt)
raw["end_dt"] = raw["end_raw"].apply(parse_dt)
raw["start_mins"] = raw["start_dt"].dt.minute
raw["end_mins"] = raw["end_dt"].dt.minute

# Check for parse failures
n_start_fail = raw["start_dt"].isna().sum()
n_end_fail = raw["end_dt"].isna().sum()
print(f"Start time parse failures: {n_start_fail}")
print(f"End time parse failures: {n_end_fail}")
if n_start_fail > 0:
    print("Failed start_raw samples:")
    failed = raw[raw["start_dt"].isna()]["start_raw"].unique()
    for s in failed[:10]:
        print(f"  {repr(s)}")

# ── Round time: if minute >= 30, add 1 hour ───────────────────────
def round_dt(dt_val):
    """Round datetime to nearest hour, with cross-day handling."""
    if pd.isna(dt_val):
        return pd.NaT
    if dt_val.minute >= 30:
        dt_val = dt_val + timedelta(hours=1)
    return dt_val.replace(minute=0, second=0, microsecond=0)


raw["start_dt_round"] = raw["start_dt"].apply(round_dt)
raw["end_dt_round"] = raw["end_dt"].apply(round_dt)

# Extract date and hour components from rounded datetimes
raw["startdate_round"] = raw["start_dt_round"].dt.date
raw["starthour_round"] = raw["start_dt_round"].dt.hour
raw["enddate_round"] = raw["end_dt_round"].dt.date
raw["endhour_round"] = raw["end_dt_round"].dt.hour

# ── Log cross-day rounding cases ───────────────────────────────────
cross_day = raw[
    (raw["start_dt"].notna()) &
    (raw["start_dt"].dt.minute >= 30) &
    (raw["start_dt"].dt.hour == 23)
].copy()
# Also check end times
cross_day_end = raw[
    (raw["end_dt"].notna()) &
    (raw["end_dt"].dt.minute >= 30) &
    (raw["end_dt"].dt.hour == 23)
].copy()

cross_day_all = pd.concat([cross_day, cross_day_end]).drop_duplicates(subset=["row_id"])
if len(cross_day_all) > 0:
    cross_day_all[["row_id", "transaction_id", "operation",
                     "start_raw", "start_dt", "start_dt_round",
                     "end_raw", "end_dt", "end_dt_round"]].to_excel(
        LOGS / "time_rounding_cross_day_cases.xlsx", index=False)
    print(f"Cross-day rounding cases logged: {len(cross_day_all)}")

# ── Parse duration to hours ───────────────────────────────────────
def parse_duration(val):
    """Parse duration string to hours (float)."""
    if pd.isna(val):
        return np.nan
    val = str(val).strip()
    if val == "-":
        return 0.0

    days = 0
    hours = 0
    minutes = 0

    # Pattern: "X days Y h Z min" or "Y h Z min" or "X days Y h" or number
    day_match = re.search(r"(\d+)\s*day[s]?", val)
    if day_match:
        days = int(day_match.group(1))

    hour_match = re.search(r"(\d+)\s*h", val)
    if hour_match:
        hours = int(hour_match.group(1))

    min_match = re.search(r"(\d+)\s*min", val)
    if min_match:
        minutes = int(min_match.group(1))

    # If it's just a plain number (no units), treat as hours
    if not day_match and not hour_match and not min_match:
        try:
            return float(val)
        except ValueError:
            return np.nan

    return days * 24 + hours + minutes / 60.0


raw["duration_hours"] = raw["duration_raw"].apply(parse_duration)

# ── Parse draught ─────────────────────────────────────────────────
def parse_draught(val):
    if pd.isna(val):
        return np.nan
    val = str(val).strip().replace(" m", "").replace("m", "")
    try:
        return float(val)
    except ValueError:
        return np.nan


raw["draught"] = raw["draught_raw"].apply(parse_draught)

# ── Identify operation types ───────────────────────────────────────
raw["is_anchorage"] = (raw["operation"] == "Anchorage").astype(int)
raw["is_sts"] = (raw["operation"] == "STS - Bunkering").astype(int)

# ── Extract supplier from STS rows ─────────────────────────────────
def extract_supplier(location_details, operation):
    """Extract supplier name from 'With XXX' in Location Details for STS rows."""
    if pd.isna(location_details) or operation != "STS - Bunkering":
        return None
    s = str(location_details).strip()
    if s.lower().startswith("with "):
        return s[5:].strip()
    return None


raw["supplier_raw"] = raw.apply(
    lambda r: extract_supplier(r["location_details"], r["operation"]), axis=1
)

# ── Match port from anchorage rows ─────────────────────────────────
port_results = raw["location_details"].apply(match_port)
raw["port_matched"] = port_results.apply(lambda x: x[0] if x else None)
raw["port_raw"] = port_results.apply(lambda x: x[1] if x else None)

# Collect unmatched anchorage locations
anchorage_rows = raw[raw["is_anchorage"] == 1]
unmatched = anchorage_rows[
    anchorage_rows["port_matched"].isna() &
    anchorage_rows["location_details"].notna() &
    anchorage_rows["location_details"].str.lower().str.startswith("at ")
]
if len(unmatched) > 0:
    unmatched_ports = unmatched[["location_details"]].drop_duplicates()
    unmatched_ports.columns = ["unmatched_location"]
    unmatched_ports.to_excel(LOGS / "unmatched_ports.xlsx", index=False)
    print(f"Unmatched port locations logged: {len(unmatched_ports)}")

# ── Flag duplicates (exact duplicate rows based on key fields) ─────
dup_cols = ["vessel_raw", "operation", "start_raw", "end_raw", "location_details"]
raw["is_duplicate"] = raw.duplicated(subset=dup_cols, keep="first").astype(int)
n_dup = raw["is_duplicate"].sum()
print(f"Duplicate rows found: {n_dup}")

if n_dup > 0:
    dup_log = raw[raw["is_duplicate"] == 1][
        ["row_id", "transaction_id", "vessel_name", "operation",
         "start_raw", "end_raw", "location_details"]
    ].copy()
    dup_log.to_excel(LOGS / "duplicate_records.xlsx", index=False)

# ── Select and order output columns ────────────────────────────────
output_cols = [
    "row_id", "transaction_id", "is_duplicate",
    "vessel_raw", "vessel_name", "vessel_code", "vessel_type",
    "in_service_commission", "dwt", "gt", "draught",
    "operation", "is_anchorage", "is_sts",
    "start_raw", "end_raw", "duration_raw", "duration_hours",
    "start_dt", "end_dt",
    "start_mins", "end_mins",
    "start_dt_round", "end_dt_round",
    "startdate_round", "starthour_round",
    "enddate_round", "endhour_round",
    "location_details", "supplier_raw",
    "port_matched", "port_raw",
]

output = raw[output_cols].copy()

# ── Save ───────────────────────────────────────────────────────────
output_path = DATA_INT / "01_bunkering_preprocessed.xlsx"
output.to_excel(output_path, index=False)
print(f"Stage 1 complete. Output: {output_path}")
print(f"Total rows: {len(output)}")
print(f"Transactions: {output['transaction_id'].nunique()}")
print(f"STS rows: {output['is_sts'].sum()}")
print(f"Anchorage rows: {output['is_anchorage'].sum()}")
print(f"Unique suppliers: {output['supplier_raw'].dropna().nunique()}")
print(f"Unique matched ports: {output['port_matched'].dropna().nunique()}")
