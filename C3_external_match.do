/*===========================================================================
 Step 3: External data matching — anchorage open/close & weather forecast
 ===========================================================================
 Matches Stage 2 transaction-level output with:
   1. 锚地开放.dta — anchorage open/close status by date-hour-port
   2. 气象预报.dta  — weather forecast index by date-hour-port

 Computes open-hour counts within +/-6h, +/-12h, +/-24h windows around
 transaction start time.

 Output: 4_bunkering_matched.dta
 ===========================================================================*/

clear all
set more off
capture log close
log using "C3_match.log", replace text

display "============================================================"
display "Step 3: External Data Matching"
display "============================================================"

/*───────────────────────────────────────────────────────────────────────────
  1. Import Stage 2 final data
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 1. Importing final transaction data ---"
import excel using "3_bunkering_final.xlsx", sheet("交易级别数据") firstrow clear

display "Transactions imported: " _N

// Parse startdate string ("DD Mon YYYY") to Stata date
gen startdate_stata = date(startdate, "DMY")
format startdate_stata %tdDD_Mon_CCYY
gen enddate_stata = date(enddate, "DMY")
format enddate_stata %tdDD_Mon_CCYY

count if missing(startdate_stata)
display "Missing start dates: " r(N)

// Ensure numeric types
destring starthour, replace force
destring supplier_n, replace force

/*───────────────────────────────────────────────────────────────────────────
  2. Load weather forecast data (气象预报.dta)
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 2. Loading weather forecast data ---"

// Load weather data once and save as tempfile
preserve
use "气象预报.dta", clear

display "Weather rows: " _N
tab port
display "Weather index distribution:"
tab 气象指数

// Standardize variable names for merging — must match expanded data names
rename hour target_hour
rename 气象指数 weather_index
rename date_numeric target_date
format target_date %tdDD_Mon_CCYY

// Save to tempfile
tempfile weather_data
save `weather_data'
restore

/*───────────────────────────────────────────────────────────────────────────
  3. Compute weather open hours — Version 1 (threshold)
     V1: weather_index 1 = closed, 2/3/4 = open
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 3. Computing V1 weather open hours ---"

foreach window in 6 12 24 {
    display "  Processing +/-`window'h window (V1)..."

    preserve
    keep transaction_id port startdate_stata starthour
    drop if missing(port) | port == ""

    // Expand to hour-level rows within the window
    gen expand_id = _n
    local total = 2 * `window' + 1
    expand `total'
    bysort expand_id: gen hour_offset = _n - `window' - 1

    // Compute target date and hour with overflow handling
    gen double target_hour_raw = starthour + hour_offset
    gen double target_date = startdate_stata + floor(target_hour_raw / 24)
    gen target_hour = mod(target_hour_raw, 24)

    keep transaction_id port target_date target_hour
    drop if missing(target_date)

    // Merge with weather data on port, date, hour
    // Use port (string), target_date, target_hour as merge keys
    merge m:1 port target_date target_hour using `weather_data', ///
        keep(master match) nogen

    // V1: weather_index >= 2 = open
    gen open_v1 = (weather_index >= 2) if !missing(weather_index)

    // Aggregate back to transaction level
    collapse (sum) openhourf_`window'_v1 = open_v1, by(transaction_id)

    tempfile v1_w`window'
    save `v1_w`window''
    restore
}

/*───────────────────────────────────────────────────────────────────────────
  4. Compute weather open hours — Version 2 (closure frequency)
     V2: expected open = 1 - closure_frequency(port, weather_index)
     closure_frequency estimated empirically from weather data
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 4. Computing V2 weather open hours ---"

// Compute empirical closure frequency from weather data
preserve
use `weather_data', clear
gen closed = (weather_index == 1)
collapse (mean) closure_freq = closed, by(port weather_index)
label variable closure_freq "Empirical P(closed | port, weather_index)"
list, clean noobs
tempfile closure_freq_table
save `closure_freq_table'
restore

foreach window in 6 12 24 {
    display "  Processing +/-`window'h window (V2)..."

    preserve
    keep transaction_id port startdate_stata starthour
    drop if missing(port) | port == ""

    gen expand_id = _n
    local total = 2 * `window' + 1
    expand `total'
    bysort expand_id: gen hour_offset = _n - `window' - 1

    gen double target_hour_raw = starthour + hour_offset
    gen double target_date = startdate_stata + floor(target_hour_raw / 24)
    gen target_hour = mod(target_hour_raw, 24)

    keep transaction_id port target_date target_hour
    drop if missing(target_date)

    // Merge with weather data
    merge m:1 port target_date target_hour using `weather_data', ///
        keep(master match) nogen

    // Merge with closure frequency table
    merge m:1 port weather_index using `closure_freq_table', ///
        keep(master match) nogen

    // V2: expected open = 1 - closure_freq
    gen open_v2 = (1 - closure_freq) if !missing(weather_index)

    collapse (sum) openhourf_`window'_v2 = open_v2, by(transaction_id)

    tempfile v2_w`window'
    save `v2_w`window''
    restore
}

/*───────────────────────────────────────────────────────────────────────────
  5. Anchorage open/close data (锚地开放.dta)
     Check availability; compute openhour_6/12/24 when file exists
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 5. Anchorage open/close matching ---"

capture confirm file "锚地开放.dta"
if _rc == 0 {
    display "  Found 锚地开放.dta — processing anchorage open hours..."
    // TODO: implement when file structure is confirmed
    // Expected variables: port, date, hour, status (open/close)
    // Logic: expand transactions +/-N hours, merge, count status=="open"
}
else {
    display "  Note: 锚地开放.dta not found — anchorage open hours set to missing."
}

/*───────────────────────────────────────────────────────────────────────────
  6. Merge all computed open-hour variables back to main data
 ───────────────────────────────────────────────────────────────────────────*/

display _n "--- 6. Merging open-hour variables ---"

// Merge V1 weather variables
foreach window in 6 12 24 {
    merge 1:1 transaction_id using `v1_w`window'', nogen
    display "  Merged openhourf_`window'_v1"
}

// Merge V2 weather variables
foreach window in 6 12 24 {
    merge 1:1 transaction_id using `v2_w`window'', nogen
    display "  Merged openhourf_`window'_v2"
}

// Fill missing = 0 for transactions with no weather match
foreach var of varlist openhourf_* {
    replace `var' = 0 if missing(`var')
}

// Anchorage open hours (set to missing)
foreach window in 6 12 24 {
    gen openhour_`window' = .
}

// Label all new variables
label variable openhourf_6_v1  "Weather open hours (+/-6h, V1 threshold: index>=2)"
label variable openhourf_12_v1 "Weather open hours (+/-12h, V1 threshold: index>=2)"
label variable openhourf_24_v1 "Weather open hours (+/-24h, V1 threshold: index>=2)"
label variable openhourf_6_v2  "Weather open hours (+/-6h, V2 1-closure_freq)"
label variable openhourf_12_v2 "Weather open hours (+/-12h, V2 1-closure_freq)"
label variable openhourf_24_v2 "Weather open hours (+/-24h, V2 1-closure_freq)"
label variable openhour_6      "Anchorage open hours (+/-6h)"
label variable openhour_12     "Anchorage open hours (+/-12h)"
label variable openhour_24     "Anchorage open hours (+/-24h)"

/*───────────────────────────────────────────────────────────────────────────
  7. Summary and save
 ───────────────────────────────────────────────────────────────────────────*/

display _n "=== 7. Summary Statistics ==="

foreach var of varlist openhourf_* {
    display _n "  `var':"
    summarize `var'
}

// Match coverage
count if openhourf_6_v1 > 0
display _n "Transactions with non-zero weather V1 match: " r(N) " / " _N

display _n "--- Saving 4_bunkering_matched.dta ---"
compress
save "4_bunkering_matched.dta", replace

display _n "Step 3 complete!"
display "Output: 4_bunkering_matched.dta"
describe, short

log close
exit, clear
