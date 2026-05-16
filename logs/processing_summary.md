# Processing Summary — 2026-05-16 20:46:25

## Data Volume
- Raw rows: 4422
- Raw transactions: 1640
- Duplicate rows removed: 193
- Final transactions: 1604
- Raw STS rows (non-dup): 2099
- Final STS slots: 2099

## STS Expansion
- max_STS: 9
- supplier_n = STS record count: PASS
- duration_STS = sum(duration_STSk): PASS
- Same-supplier multi-STS cases: 100

## Port Matching
- Port match rate: 98.1%
- Multi-port transactions: 26
- All ports from valid table: PASS

## Anchor Open Matching
- Match rate (all transactions): 98.1%
- Match rate (transactions with port): 100.0%
- openhour_6 mean: 9.3
- openhour_12 mean: 17.8
- openhour_24 mean: 34.7

## Weather Forecast Matching
- Match rate (all transactions): 98.1%
- match rate (with port): 100.0%
- v1 openhourf_6 mean: 9.7
- v1 openhourf_12 mean: 18.6
- v1 openhourf_24 mean: 36.4
- v2 openhourf_6 mean (provisional): 7.7
- v2 openhourf_12 mean (provisional): 14.7
- v2 openhourf_24 mean (provisional): 28.8

## Warnings
- v2 closure frequency is PROVISIONAL: {1: 1.0, 2: 0.5, 3: 0.2, 4: 0.0}
- Replace with actual closure frequency table before final delivery.

## Log Files
- unmatched_ports.xlsx
- multi_port_transactions.xlsx
- duplicate_records.xlsx
- multi_sts_cases.xlsx
- same_supplier_multi_sts_cases.xlsx
- time_rounding_cross_day_cases.xlsx
