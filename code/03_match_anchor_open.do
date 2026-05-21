/* Stage 3: Match anchor open data to transaction-level data.

   Input:
     data_intermediate/02_transaction_level_base.xlsx
     data_raw/锚地开放.dta

   Output:
     data_intermediate/03_transaction_with_anchor.dta

   For each transaction, compute openhour_6, openhour_12, openhour_24
   around the transaction start date-hour and keep all transaction rows.
*/

version 17
set more off
clear all

* ── Import transaction-level base ──────────────────────────────
import excel using "data_intermediate/02_transaction_level_base.xlsx", firstrow clear

capture confirm string variable port
if _rc {
    tostring port, replace force
}
replace port = strtrim(port)
replace port = "" if port == "."

capture confirm numeric variable starthour
if _rc {
    destring starthour, replace force
}

capture confirm numeric variable startdate
if !_rc {
    gen str10 startdate_str = string(startdate, "%tdCCYY-NN-DD")
}
else {
    gen str10 startdate_str = startdate
}
gen double start_dt = clock(startdate_str + " " + string(starthour, "%02.0f") + ":00:00", "YMDhms")
format start_dt %tc
drop startdate_str

tempfile tx_all tx_match tx_expanded anchor_data hist_open
save `tx_all', replace

preserve
    keep transaction_id port start_dt
    drop if missing(port) | port == ""
    drop if missing(start_dt)

    expand 49
    bysort transaction_id: gen offset = _n - 25
    gen double match_dt = start_dt + offset * 3600000
    format match_dt %tc
    gen match_date = dofc(match_dt)
    format match_date %td
    gen match_hour = hh(match_dt)

    gen byte in_6 = abs(offset) <= 6
    gen byte in_12 = abs(offset) <= 12
    gen byte in_24 = abs(offset) <= 24

    keep transaction_id port start_dt offset match_date match_hour in_*
    save `tx_match', replace
restore

* ── Prepare date-hour-port anchor open data ────────────────────
use "data_raw/锚地开放.dta", clear
capture confirm string variable port
if _rc {
    tostring port, replace force
}
replace port = strtrim(port)

gen double anchor_dt = dhms(date_numeric, hour, 0, 0)
format anchor_dt %tc
gen byte open_flag = (strupper(strtrim(status)) == "OPEN")

rename date_numeric match_date
rename hour match_hour
keep port match_date match_hour open_flag
collapse (max) open_flag, by(port match_date match_hour)
save `anchor_data', replace

* ── Merge fixed transaction windows and collapse window sums ─────
use `tx_match', clear
merge m:1 port match_date match_hour using `anchor_data', keep(master match)

foreach w in 6 12 24 {
    gen byte matched_in_`w' = (_merge == 3) & in_`w'
    replace open_flag = 0 if missing(open_flag)
    gen double open_in_`w' = open_flag * in_`w'
    gen byte cov_in_`w' = matched_in_`w'
}

collapse ///
    (sum) openhour_6 = open_in_6 ///
          openhour_12 = open_in_12 ///
          openhour_24 = open_in_24 ///
          anchor_window_coverage_6 = cov_in_6 ///
          anchor_window_coverage_12 = cov_in_12 ///
          anchor_window_coverage_24 = cov_in_24, ///
    by(transaction_id)

gen byte anchor_match_flag = anchor_window_coverage_24 > 0
foreach w in 6 12 24 {
    replace openhour_`w' = . if anchor_window_coverage_`w' == 0
}
save `hist_open', replace

* ── Merge back to all transactions ─────────────────────────────
use `tx_all', clear
merge 1:1 transaction_id using `hist_open', nogen

replace anchor_match_flag = 0 if missing(anchor_match_flag)
foreach v in anchor_window_coverage_6 anchor_window_coverage_12 anchor_window_coverage_24 {
    replace `v' = 0 if missing(`v')
}

drop start_dt
save "data_intermediate/03_transaction_with_anchor.dta", replace

display _n "=== Stage 3 Summary ==="
count
display "Transactions retained: " r(N)
count if anchor_match_flag == 1
display "Anchor matched: " r(N)
count if anchor_match_flag == 0
display "Anchor unmatched: " r(N)
summarize openhour_6 openhour_12 openhour_24
display "=== Stage 3 complete ==="
