clear all
set more off
set maxvar 10000

capture log close
log using "C4_analysis.log", replace

di "Stage 4: Statistical Analysis"
di "=================================================="

di "Loading final matched dataset..."
use "4_bunkering_matched.dta", clear
di "  Observations: " _N
di "  Variables: " c(k)

* ============================================================
* Part A: Descriptive Statistics
* ============================================================
di ""
di "Part A: Descriptive Statistics"
di "=================================================="

di "Transaction-level variables:"
summarize duration supplier_n draught

di "Anchorage open hours:"
summarize openhour_6 openhour_12 openhour_24

di "Weather forecast open hours (V1 threshold):"
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1

di "Weather forecast open hours (V2 probability):"
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2

* ============================================================
* Part B: Port Comparison
* ============================================================
di ""
di "Part B: Port Comparison"
di "=================================================="

encode port, gen(port_id)
tab port

di "Mean duration by port:"
bysort port: summarize duration

di "Mean openhour_6 by port:"
bysort port: summarize openhour_6

di "Mean openhourf_6_v1 by port:"
bysort port: summarize openhourf_6_v1

di "Mean openhourf_6_v2 by port:"
bysort port: summarize openhourf_6_v2

di "Mean supplier_n by port:"
bysort port: summarize supplier_n

di "Count by port:"
tab port

* ============================================================
* Part C: Correlation Matrix
* ============================================================
di ""
di "Part C: Correlation Matrix"
di "=================================================="

correlate duration openhour_6 openhour_12 openhour_24 ///
    openhourf_6_v1 openhourf_12_v1 openhourf_24_v1 ///
    openhourf_6_v2 openhourf_12_v2 openhourf_24_v2 supplier_n

* ============================================================
* Part D: Regression Analysis
* ============================================================
di ""
di "Part D: Regression Analysis"
di "=================================================="

di "Regression: duration ~ openhour_24 + supplier_n"
regress duration openhour_24 supplier_n

di "Regression with port fixed effects:"
regress duration openhour_24 openhourf_24_v1 openhourf_24_v2 supplier_n i.port_id

di "Regression: duration ~ openhour_6 + openhourf_6_v1 + openhourf_6_v2"
regress duration openhour_6 openhourf_6_v1 openhourf_6_v2 supplier_n

* ============================================================
* Part E: Export Port Summary
* ============================================================
di ""
di "Part E: Exporting Port Summary"
di "=================================================="

collapse (count) n_transactions = transaction_id ///
    (mean) mean_duration = duration ///
    (mean) mean_supplier_n = supplier_n ///
    (mean) mean_openhour_6 = openhour_6 ///
    (mean) mean_openhour_12 = openhour_12 ///
    (mean) mean_openhour_24 = openhour_24 ///
    (mean) mean_openhourf_6_v1 = openhourf_6_v1 ///
    (mean) mean_openhourf_12_v1 = openhourf_12_v1 ///
    (mean) mean_openhourf_24_v1 = openhourf_24_v1 ///
    (mean) mean_openhourf_6_v2 = openhourf_6_v2 ///
    (mean) mean_openhourf_12_v2 = openhourf_12_v2 ///
    (mean) mean_openhourf_24_v2 = openhourf_24_v2, by(port)

di "Port summary table:"
list, noobs

export excel "C4_port_summary.xlsx", firstrow(variables) replace
di "Exported: C4_port_summary.xlsx"

di ""
di "Stage 4 (Statistical Analysis) complete!"
di "Final output: C4_port_summary.xlsx"
log close
exit
