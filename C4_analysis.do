/*===========================================================================
 Step 4: Statistical analysis — bunkering transaction data
 ===========================================================================
 Reads 4_bunkering_matched.dta and produces:
   - Descriptive statistics tables
   - Port comparison analysis
   - Waiting time vs weather open hours analysis
   - STS duration analysis by supplier count

 Output: analysis outputs to log file + optional export tables
 ===========================================================================*/

clear all
set more off
capture log close
log using "C4_analysis.log", replace text

display "============================================================"
display "Step 4: Statistical Analysis"
display "============================================================"

/*───────────────────────────────────────────────────────────────────────────
  1. Load matched data
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 1. Loading matched data ---"
capture confirm file "4_bunkering_matched.dta"
if _rc != 0 {
    display as error "4_bunkering_matched.dta not found. Run C3_external_match.do first."
    exit 601
}

use "4_bunkering_matched.dta", clear
describe
count
display "Total transactions: " r(N)

/*───────────────────────────────────────────────────────────────────────────
  2. Data preparation
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 2. Data preparation ---"

// Ensure numeric types
foreach var in duration duration_STS dwt gt supplier_n starthour endhour {
    capture confirm string variable `var'
    if _rc == 0 {
        destring `var', replace force
    }
}

// Generate derived variables
// Waiting time = total duration - STS duration (approximate anchorage waiting)
gen waiting_hours = duration - duration_STS
replace waiting_hours = . if waiting_hours < 0
label variable waiting_hours "Estimated waiting hours (total - STS)"

// Log transform for skewed duration variables
gen ln_duration = ln(duration)
gen ln_waiting = ln(waiting_hours + 1)
label variable ln_duration "ln(total duration)"
label variable ln_waiting "ln(waiting hours + 1)"

// Multi-supplier indicator
gen multi_supplier = (supplier_n >= 2) if !missing(supplier_n)
label variable multi_supplier "Has 2+ unique suppliers"
label define multi_lbl 0 "Single supplier" 1 "Multi supplier"
label values multi_supplier multi_lbl

// Port factor
encode port, gen(port_id)
label variable port_id "Port (factored)"

/*───────────────────────────────────────────────────────────────────────────
  3. Descriptive statistics
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 3. Descriptive Statistics ==="

display _n "--- Transaction-level summary ---"
summarize duration waiting_hours duration_STS draught ///
    dwt gt supplier_n

display _n "--- By port ---"
bysort port: summarize duration waiting_hours duration_STS ///
    if !missing(port) & port != ""

display _n "--- By supplier count ---"
bysort multi_supplier: summarize duration waiting_hours duration_STS ///
    if !missing(multi_supplier)

/*───────────────────────────────────────────────────────────────────────────
  4. Port comparison
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 4. Port Comparison ==="

display _n "--- Transaction counts by port ---"
tab port if !missing(port) & port != ""

display _n "--- Average duration by port ---"
table port if !missing(port) & port != "", ///
    statistic(mean duration) ///
    statistic(mean waiting_hours) ///
    statistic(mean duration_STS) ///
    statistic(count transaction_id)

/*───────────────────────────────────────────────────────────────────────────
  5. Weather open hours vs waiting time
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 5. Weather Analysis ==="

// Check if weather variables exist
capture confirm variable openhourf_6_v1
if _rc == 0 {
    display _n "--- Weather open hours summary ---"
    summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1 ///
        openhourf_6_v2 openhourf_12_v2 openhourf_24_v2

    display _n "--- Correlation: weather V1 open hours vs waiting ---"
    foreach window in 6 12 24 {
        capture confirm variable openhourf_`window'_v1
        if _rc == 0 {
            correlate waiting_hours openhourf_`window'_v1 ///
                if !missing(openhourf_`window'_v1)
            display "  correlation(waiting, openhourf_`window'_v1) = " r(rho)
        }
    }

    display _n "--- Port-level weather effects ---"
    foreach wport in "条帚门" "秀山东" "虾峙门" "衢山" "马峙" {
        count if port == "`wport'" & !missing(openhourf_12_v1)
        if r(N) >= 30 {
            display _n "  Port: `wport'"
            quietly summarize waiting_hours ///
                if port == "`wport'" & openhourf_12_v1 >= 20
            local high = r(mean)
            quietly summarize waiting_hours ///
                if port == "`wport'" & openhourf_12_v1 < 20
            local low = r(mean)
            display "    Avg waiting when open ≥20h in ±12h: " %5.1f `high'
            display "    Avg waiting when open <20h in ±12h: " %5.1f `low'
        }
    }
}
else {
    display "  Weather variables not found — run C3_external_match.do first."
}

/*───────────────────────────────────────────────────────────────────────────
  6. Regression analysis
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 6. Regression Analysis ==="

// Model 1: Waiting time ~ weather open hours (if weather data available)
capture confirm variable openhourf_12_v1
if _rc == 0 {
    display _n "--- Model 1: Waiting hours vs weather (V1, ±12h window) ---"
    quietly regress waiting_hours openhourf_12_v1
    estimates store m1

    display _n "--- Model 2: Add port fixed effects ---"
    quietly regress waiting_hours openhourf_12_v1 i.port_id
    estimates store m2

    display _n "--- Model 3: Add vessel characteristics ---"
    quietly regress waiting_hours openhourf_12_v1 i.port_id dwt gt
    estimates store m3

    estimates table m1 m2 m3, ///
        star(0.10 0.05 0.01) stats(N r2 r2_a)
}

// Model 4: STS duration ~ supplier count
display _n "--- Model 4: STS duration vs supplier count ---"
regress duration_STS supplier_n if supplier_n >= 1
estimates store m4

display _n "--- Model 5: STS duration vs supplier count, controlling for port ---"
regress duration_STS supplier_n i.port_id if supplier_n >= 1
estimates store m5

estimates table m4 m5, star(0.10 0.05 0.01) stats(N r2 r2_a)

/*───────────────────────────────────────────────────────────────────────────
  7. Supplier count analysis
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 7. Supplier Count Analysis ==="

display _n "--- Supplier count distribution ---"
tab supplier_n if supplier_n >= 1

display _n "--- Average STS characteristics by supplier count ---"
table supplier_n if supplier_n >= 1 & supplier_n <= 5, ///
    statistic(mean duration_STS) ///
    statistic(mean duration) ///
    statistic(count transaction_id)

/*───────────────────────────────────────────────────────────────────────────
  8. Export summary tables (optional CSV)
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 8. Export Summary Tables ==="

// Port-level summary
preserve
collapse (mean) avg_duration=duration avg_waiting=waiting_hours ///
    avg_duration_STS=duration_STS (count) n=transaction_id, by(port)
drop if missing(port) | port == ""
list, clean
export excel using "C4_port_summary.xlsx", firstrow(variables) replace
restore

display _n "Step 4 complete!"
display "Port summary exported to C4_port_summary.xlsx"

log close
exit, clear
