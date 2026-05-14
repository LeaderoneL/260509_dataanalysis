# Bunkering Data Pipeline

Ship bunkering record transaction processing pipeline — 4 stages.

## Pipeline

| Stage | Script | Language | Description |
|-------|--------|----------|-------------|
| 1 | `C1_preprocess_bunkering.py` | Python | Time standardization + field parsing |
| 2 | `C2_finalize_bunkering.py` | Python | Transaction-level aggregation + STS expansion |
| 3 | `C3_external_match.do` | Stata | External data matching (anchorage + weather) |
| 4 | `C4_analysis.do` | Stata | Statistical analysis + regression |

## Files

| File | Type | Description |
|------|------|-------------|
| `Bunkering Record v3.xlsx` | Input | Raw bunkering records (corrected v3) |
| `锚地开放.dta` | Input | Anchorage open/close status by port-date-hour |
| `气象预报.dta` | Input | Weather forecast index by port-date-hour |
| `2_bunkering_preprocessed.xlsx` | Output | Stage 1 preprocessed data (30 cols, 4422 rows) |
| `3_bunkering_final.xlsx` | Output | Stage 2 transaction-level data (49 cols, 1543 rows) |
| `4_bunkering_matched.dta` | Output | Stage 3 matched data (60 vars, 1543 rows) |
| `C4_port_summary.xlsx` | Output | Stage 4 port-level summary table |
| `docs/data_processing_requirements.html` | Doc | Full data processing specification |

## Usage

```bash
# Stage 1 & 2 (Python)
python3 C1_preprocess_bunkering.py
python3 C2_finalize_bunkering.py

# Stage 3 & 4 (Stata)
stata-mp -b -e 'do C3_external_match.do'
stata-mp -b -e 'do C4_analysis.do'
```

## Requirements

- Python 3.9+ (pandas, openpyxl)
- StataNow 19+ MP

## Author

QiXiang Lei <leiqixiang01@163.com>
