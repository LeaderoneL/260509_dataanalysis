clear all
set more off
set maxvar 10000

capture log close
log using "C4_analysis.log", replace

di "Stage 4: Statistical Analysis"
di "=================================================="

use "4_bunkering_matched.dta", clear
di "Dataset: " _N " observations, " c(k) " variables"

* ============================================================
* Part A: Descriptive Statistics
* ============================================================
di ""
di "Part A: Descriptive Statistics"
di "=================================================="

di "Transaction-level variables:"
summarize duration supplier_n draught

di "Anchorage open hours (openhour_6/12/24):"
summarize openhour_6 openhour_12 openhour_24

di "Weather forecast V1 (threshold):"
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1

di "Weather forecast V2 (probability):"
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2

* ============================================================
* Part B: Port Comparison
* ============================================================
di ""
di "Part B: Port Comparison"
di "=================================================="

encode port, gen(port_id)
tab port

foreach var in duration supplier_n openhour_6 openhourf_6_v1 openhourf_6_v2 {
    di ""
    di "Mean `var' by port:"
    bysort port: summarize `var'
}

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

di "(1) Base model: duration ~ openhour_24 + supplier_n"
regress duration openhour_24 supplier_n

di ""
di "(2) Port fixed effects: duration ~ openhour_24 + openhourf_24_v1 + openhourf_24_v2 + supplier_n + i.port"
regress duration openhour_24 openhourf_24_v1 openhourf_24_v2 supplier_n i.port_id

di ""
di "(3) 6h window model: duration ~ openhour_6 + openhourf_6_v1 + openhourf_6_v2 + supplier_n"
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

list, noobs
export excel "C4_port_summary.xlsx", firstrow(variables) replace

di ""
di "Stage 4 complete!"
di "Output: C4_port_summary.xlsx"
log close
