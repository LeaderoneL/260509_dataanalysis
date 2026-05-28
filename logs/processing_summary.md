# Processing Summary — 2026-05-26 21:36:07

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
- end_STS_final = last STS endpoint: PASS
- Same-supplier multi-STS cases: 100

## Port Matching
- Port match rate: 98.1%
- Multi-port transactions: 26
- All ports from valid table: PASS

## Anchor Open Matching
- Match rate (all transactions): 90.0%
- Match rate (transactions with port): 91.7%
- openhour_6 mean: 10.1
- openhour_12 mean: 19.5
- openhour_24 mean: 37.9

## Weather Forecast Matching
- Match rate (all transactions): 87.7%
- match rate (with port): 89.4%
- v1 openhourf_6 mean: 10.8
- v1 openhourf_12 mean: 20.8
- v1 openhourf_24 mean: 40.7
- v2 openhourf_6 mean: 9.5
- v2 openhourf_12 mean: 18.2
- v2 openhourf_24 mean: 35.6
- v3 openhourf_6 mean: 9.3
- v3 openhourf_12 mean: 17.9
- v3 openhourf_24 mean: 35.0

## Window Coverage
- Anchor 6h: full=1443, partial=0, no coverage=161
- Anchor 12h: full=1443, partial=0, no coverage=161
- Anchor 24h: full=1443, partial=0, no coverage=161
- Weather 6h: full=1403, partial=1, no coverage=200
- Weather 12h: full=1400, partial=5, no coverage=199
- Weather 24h: full=1400, partial=7, no coverage=197

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
