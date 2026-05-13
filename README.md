# Bunkering Data Pipeline

Ship bunkering record transaction processing pipeline.

## Files

| File | Description |
|------|-------------|
| `C1_preprocess_bunkering.py` | Stage 1: time standardization + field parsing |
| `C2_finalize_bunkering.py` | Stage 2: transaction-level aggregation |
| `1_Bunkering_Record_revised_transaction.xlsx` | Raw input data |
| `2_bunkering_preprocessed.xlsx` | Intermediate preprocessed output |
| `3_bunkering_final.xlsx` | Final transaction-level output |
| `docs/bunkering_pipeline_documentation.html` | Full documentation |

## Usage

```bash
python3 C1_preprocess_bunkering.py
python3 C2_finalize_bunkering.py
```

## Requirements

- Python 3.9+
- pandas
- openpyxl

## Author

QiXiang Lei <leiqixiang01@163.com>
