/* Stage 3: Match anchor open data to transaction-level data.

   For each transaction, compute openhour_6, openhour_12, openhour_24
   based on the anchor open status around the transaction start time.

   Run: stata-mp < code/03_match_anchor_open.do
*/

set more off
clear all

* ── Import transaction-level base ──────────────────────────────
import excel using "data_intermediate/02_transaction_level_base.xlsx", sheet("Sheet1") firstrow clear

* Keep needed variables
keep transaction_id port startdate starthour

* Drop transactions with empty port
drop if missing(port)
replace port = strtrim(port)
drop if port == ""

* Parse start datetime
gen double start_dt = clock(startdate + " " + string(starthour, "%02.0f") + ":00:00", "YMDhms")
format start_dt %tc

* Save
tempfile tx
save `tx', replace

* ── Load anchor open data ──────────────────────────────────────
use "data_raw/锚地开放.dta", clear

* Ensure port is string and trimmed
tostring port, replace force
replace port = strtrim(port)

* Create datetime for anchor records
gen double anchor_dt = clock(string(date_numeric, "%tdCCYY-NN-DD") + " " + string(hour, "%02.0f") + ":00:00", "YMDhms")
format anchor_dt %tc

* Open flag
gen byte open_flag = (strupper(status) == "OPEN")

keep port anchor_dt open_flag

* Index for faster lookups
sort port anchor_dt
save `tx', replace

* ── Match using frame-based lookup ─────────────────────────────
use `tx', clear

gen openhour_6 = .
gen openhour_12 = .
gen openhour_24 = .
gen anchor_match_flag = 0
gen anchor_window_coverage_6 = 0
gen anchor_window_coverage_12 = 0
gen anchor_window_coverage_24 = 0

* Create a frame with anchor data
frame create anchor_data
frame anchor_data: use `tx', clear

* Process each transaction
quietly {
    count
    local N = r(N)

    forvalues i = 1/`N' {
        local p = port[`i']
        local t = start_dt[`i']

        * Window boundaries (ms)
        local t_m6  = `t' -  6 * 3600000
        local t_p6  = `t' +  6 * 3600000
        local t_m12 = `t' - 12 * 3600000
        local t_p12 = `t' + 12 * 3600000
        local t_m24 = `t' - 24 * 3600000
        local t_p24 = `t' + 24 * 3600000

        * Check if port exists in anchor data
        frame anchor_data {
            count if port == "`p'"
        }
        if r(N) > 0 {
            replace anchor_match_flag = 1 in `i'

            * Window 6
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m6' & anchor_dt <= `t_p6'
            }
            local tot6 = r(N)
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m6' & anchor_dt <= `t_p6' & open_flag == 1
            }
            replace openhour_6 = r(N) in `i'
            replace anchor_window_coverage_6 = `tot6' in `i'

            * Window 12
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m12' & anchor_dt <= `t_p12'
            }
            local tot12 = r(N)
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m12' & anchor_dt <= `t_p12' & open_flag == 1
            }
            replace openhour_12 = r(N) in `i'
            replace anchor_window_coverage_12 = `tot12' in `i'

            * Window 24
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m24' & anchor_dt <= `t_p24'
            }
            local tot24 = r(N)
            frame anchor_data {
                count if port == "`p'" & anchor_dt >= `t_m24' & anchor_dt <= `t_p24' & open_flag == 1
            }
            replace openhour_24 = r(N) in `i'
            replace anchor_window_coverage_24 = `tot24' in `i'
        }
    }
}

drop start_dt

* ── Save ───────────────────────────────────────────────────────
save "data_intermediate/03_transaction_with_anchor.dta", replace

* ── Summary ────────────────────────────────────────────────────
display _n "=== Stage 3 Summary ==="
count
display "Transactions processed: " r(N)
count if anchor_match_flag == 1
display "Anchor matched: " r(N)
count if anchor_match_flag == 0
display "Anchor unmatched: " r(N)
summarize openhour_6 openhour_12 openhour_24
display "=== Stage 3 complete ==="
