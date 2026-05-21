/* Stage 4: Match weather forecast data to transaction-level data.

   Input:
     data_intermediate/03_transaction_with_anchor.dta
     data_raw/气象预报.dta

   Output:
     data_intermediate/04_transaction_with_weather.dta

   For each transaction, compute:
     v1: MIO 1 = closed; MIO 2/3/4 = open
     v2: average open probability from closure_frequency.csv
         MIO 1 = 0.28, MIO 2 = 0.73, MIO 3 = 0.87, MIO 4 = 0.88
*/

version 17
set more off
clear all

* ── Import transaction data with anchor results ─────────────────
use "data_intermediate/03_transaction_with_anchor.dta", clear

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

tempfile tx_all tx_match weather_data weather_open
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

* ── Prepare date-hour-port weather data ─────────────────────────
use "data_raw/气象预报.dta", clear
capture confirm string variable port
if _rc {
    tostring port, replace force
}
replace port = strtrim(port)

capture rename 气象指数 windex
capture confirm numeric variable windex
if _rc {
    destring windex, replace force
}

gen byte open_v1 = inlist(windex, 2, 3, 4)
gen double open_v2 = .
replace open_v2 = 0.28 if windex == 1
replace open_v2 = 0.73 if windex == 2
replace open_v2 = 0.87 if windex == 3
replace open_v2 = 0.88 if windex == 4

rename date_numeric match_date
rename hour match_hour
keep port match_date match_hour open_v1 open_v2
collapse (max) open_v1 (mean) open_v2, by(port match_date match_hour)
save `weather_data', replace

* ── Merge fixed transaction windows and collapse window sums ─────
use `tx_match', clear
merge m:1 port match_date match_hour using `weather_data', keep(master match)

foreach w in 6 12 24 {
    gen byte matched_in_`w' = (_merge == 3) & in_`w'
    replace open_v1 = 0 if missing(open_v1)
    replace open_v2 = 0 if missing(open_v2)
    gen double openf_v1_in_`w' = open_v1 * in_`w'
    gen double openf_v2_in_`w' = open_v2 * in_`w'
    gen byte cov_in_`w' = matched_in_`w'
}

collapse ///
    (sum) openhourf_6_v1 = openf_v1_in_6 ///
          openhourf_12_v1 = openf_v1_in_12 ///
          openhourf_24_v1 = openf_v1_in_24 ///
          openhourf_6_v2 = openf_v2_in_6 ///
          openhourf_12_v2 = openf_v2_in_12 ///
          openhourf_24_v2 = openf_v2_in_24 ///
          weather_window_coverage_6 = cov_in_6 ///
          weather_window_coverage_12 = cov_in_12 ///
          weather_window_coverage_24 = cov_in_24, ///
    by(transaction_id)

gen byte weather_match_flag = weather_window_coverage_24 > 0
foreach w in 6 12 24 {
    replace openhourf_`w'_v1 = . if weather_window_coverage_`w' == 0
    replace openhourf_`w'_v2 = . if weather_window_coverage_`w' == 0
}
save `weather_open', replace

* ── Merge back to all transactions ─────────────────────────────
use `tx_all', clear
merge 1:1 transaction_id using `weather_open', nogen

replace weather_match_flag = 0 if missing(weather_match_flag)
foreach v in weather_window_coverage_6 weather_window_coverage_12 weather_window_coverage_24 {
    replace `v' = 0 if missing(`v')
}

drop start_dt
save "data_intermediate/04_transaction_with_weather.dta", replace

display _n "=== Stage 4 Summary ==="
count
display "Transactions retained: " r(N)
count if weather_match_flag == 1
display "Weather matched: " r(N)
count if weather_match_flag == 0
display "Weather unmatched: " r(N)
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2
display "NOTE: v2 uses Average closure frequency: 1=.72, 2=.27, 3=.13, 4=.12"
display "=== Stage 4 complete ==="
