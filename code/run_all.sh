#!/bin/bash
# Full pipeline: Bunkering Transaction Data Processing
# Usage: bash code/run_all.sh

set -e
cd "$(dirname "$0")/.."

echo "=========================================="
echo "Bunkering Transaction Data Processing"
echo "=========================================="
echo ""

# Stage 1: Preprocessing
echo "[1/5] Running Stage 1: Preprocessing..."
python3 code/01_preprocess_bunkering.py
echo ""

# Stage 2: Transaction-level building
echo "[2/5] Running Stage 2: Transaction-level Building..."
python3 code/02_build_transaction_level.py
echo ""

# Stage 3: Anchor open matching
echo "[3/5] Running Stage 3: Anchor Open Matching..."
python3 code/03_match_anchor_open.py
echo ""

# Stage 4: Weather forecast matching
echo "[4/5] Running Stage 4: Weather Forecast Matching..."
python3 code/04_match_weather_forecast.py
echo ""

# Stage 5: Quality checks
echo "[5/5] Running Stage 5: Quality Checks..."
python3 code/05_quality_checks.py
echo ""

echo "=========================================="
echo "Pipeline Complete!"
echo "=========================================="
echo ""
echo "Outputs:"
echo "  data_final/bunkering_transaction_final.dta"
echo "  data_final/bunkering_transaction_final.xlsx"
echo "  logs/processing_summary.md"
