# Processing Summary — 2026-05-30 02:04:09

## Data Volume
- Raw rows: 4422
- Raw transactions: 1640
- Duplicate rows removed: 193
- Final transactions: 1559
- Raw STS rows (non-dup): 2099
- Raw STS rows in retained transactions: 2084
- Final STS slots: 2084

## STS Expansion
- max_STS: 9
- supplier_n = STS record count: PASS
- duration_STS = sum(duration_STSk): PASS
- duration_STSk >0 and <1h: 90
- duration_STSk ==0h: 31
- end_STS_final = last STS endpoint: PASS
- Same-supplier multi-STS cases: 100

## Port Matching
- Port match rate: 98.7%
- Multi-port transactions: 30
- All ports from valid table: PASS

## Anchor Open Matching
- Match rate (all transactions): 90.2%
- Match rate (transactions with port): 91.4%
- openhour_6 mean: 9.3
- openhour_12 mean: 18.7
- openhour_24 mean: 37.1

## Weather Forecast Matching
- Match rate (all transactions): 87.8%
- match rate (with port): 89.0%
- v1 openhourf_6 mean: 10.0
- v1 openhourf_12 mean: 19.9
- v1 openhourf_24 mean: 39.8
- v2 openhourf_6 mean: 8.7
- v2 openhourf_12 mean: 17.5
- v2 openhourf_24 mean: 34.9
- v3 openhourf_6 mean: 8.6
- v3 openhourf_12 mean: 17.1
- v3 openhourf_24 mean: 34.2

## Window Coverage
- Anchor 6h: full=1406, partial=0, no coverage=153
- Anchor 12h: full=1406, partial=0, no coverage=153
- Anchor 24h: full=1406, partial=0, no coverage=153
- Weather 6h: full=1364, partial=2, no coverage=193
- Weather 12h: full=1361, partial=6, no coverage=192
- Weather 24h: full=1361, partial=8, no coverage=190

## Closure Frequency Source
- closure_frequency.csv: Average closure frequencies
- v2 uses Average open probability = 1 - Average closure_frequency
- v3 uses port-specific open probability = 1 - port-specific closure_frequency

## Log Files
- unmatched_ports.xlsx
- multi_port_transactions.xlsx
- duplicate_records.xlsx
- multi_sts_cases.xlsx
- same_supplier_multi_sts_cases.xlsx
- time_rounding_cross_day_cases.xlsx
