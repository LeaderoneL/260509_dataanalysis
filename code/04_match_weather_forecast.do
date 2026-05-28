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
     v3: port-specific open probability from closure_frequency.csv
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

tempfile tx_all tx_match weather_data weather_open closure_prob
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

    gen byte in_6 = offset >= -6 & offset <= 5
    gen byte in_12 = offset >= -12 & offset <= 11
    gen byte in_24 = offset >= -24 & offset <= 23

    keep transaction_id port start_dt offset match_date match_hour in_*
    save `tx_match', replace
restore

* ── Prepare port-specific open probabilities ─────────────────────
preserve
    * CSV row 1 is a title ("Table 1:..."), row 2 is the real header.
    * Use varnames(2) so rows 1-2 are combined as variable names, and
    * rowrange(3:6) to import only the 4 data rows (MIO 1-4).
    * Columns are identified by header keywords, not by position.
    import delimited using "data_raw/closure_frequency.csv", ///
        varnames(2) rowrange(3:6) stringcols(_all) clear

    * Map columns to standard names by matching keywords in the header text.
    * The original CSV headers are: MIO, Tiaozhoumen, Xiushan East,
    * Xiazhimen, Qushan, Mazhi, Average.
    qui ds
    local allvars `r(varlist)'
    local nvars : word count `allvars'

    forval i = 1/`nvars' {
        local oldname : word `i' of `allvars'
        local lname = lower("`oldname'")

        if strpos("`lname'", "mio") {
            rename `oldname' windex
        }
        else if strpos("`lname'", "tiaozhoumen") {
            rename `oldname' cf_tiaozhoumen
        }
        else if strpos("`lname'", "xiushan") & strpos("`lname'", "east") {
            rename `oldname' cf_xiushan_east
        }
        else if strpos("`lname'", "xiazhimen") {
            rename `oldname' cf_xiazhimen
        }
        else if strpos("`lname'", "qushan") {
            rename `oldname' cf_qushan
        }
        else if strpos("`lname'", "mazhi") {
            rename `oldname' cf_mazhi
        }
        * "Average" column: intentionally left unmatched — dropped by keep below
    }

    keep windex cf_*
    destring windex, replace force

    foreach v of varlist cf_* {
        replace `v' = subinstr(`v', "%", "", .)
        destring `v', replace force
        replace `v' = 1 - `v' / 100
    }

    rename cf_tiaozhoumen open_tiaozhoumen
    rename cf_xiushan_east open_xiushan_east
    rename cf_xiazhimen open_xiazhimen
    rename cf_qushan open_qushan
    rename cf_mazhi open_mazhi

    reshape long open_, i(windex) j(port_code) string
    rename open_ open_v3

    gen str20 port = ""
    replace port = "条帚门" if port_code == "tiaozhoumen"
    replace port = "秀山东" if port_code == "xiushan_east"
    replace port = "虾峙门" if port_code == "xiazhimen"
    replace port = "衢山" if port_code == "qushan"
    replace port = "马峙" if port_code == "mazhi"

    keep port windex open_v3
    save `closure_prob', replace
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
merge m:1 port windex using `closure_prob', keep(master match) nogen

count if missing(open_v3) & inlist(windex, 1, 2, 3, 4) & !missing(port)
assert r(N) == 0

rename date_numeric match_date
rename hour match_hour
keep port match_date match_hour open_v1 open_v2 open_v3
collapse (max) open_v1 (mean) open_v2 open_v3, by(port match_date match_hour)
save `weather_data', replace

* ── Merge fixed transaction windows and collapse window sums ─────
use `tx_match', clear
merge m:1 port match_date match_hour using `weather_data', keep(master match)

foreach w in 6 12 24 {
    gen byte matched_in_`w' = (_merge == 3) & in_`w'
    replace open_v1 = 0 if missing(open_v1)
    replace open_v2 = 0 if missing(open_v2)
    replace open_v3 = 0 if missing(open_v3)
    gen double openf_v1_in_`w' = open_v1 * in_`w'
    gen double openf_v2_in_`w' = open_v2 * in_`w'
    gen double openf_v3_in_`w' = open_v3 * in_`w'
    gen byte cov_in_`w' = matched_in_`w'
}

collapse ///
    (sum) openhourf_6_v1 = openf_v1_in_6 ///
          openhourf_12_v1 = openf_v1_in_12 ///
          openhourf_24_v1 = openf_v1_in_24 ///
          openhourf_6_v2 = openf_v2_in_6 ///
          openhourf_12_v2 = openf_v2_in_12 ///
          openhourf_24_v2 = openf_v2_in_24 ///
          openhourf_6_v3 = openf_v3_in_6 ///
          openhourf_12_v3 = openf_v3_in_12 ///
          openhourf_24_v3 = openf_v3_in_24 ///
          weather_window_coverage_6 = cov_in_6 ///
          weather_window_coverage_12 = cov_in_12 ///
          weather_window_coverage_24 = cov_in_24, ///
    by(transaction_id)

gen byte weather_match_flag = weather_window_coverage_24 > 0
foreach w in 6 12 24 {
    replace openhourf_`w'_v1 = . if weather_window_coverage_`w' == 0
    replace openhourf_`w'_v2 = . if weather_window_coverage_`w' == 0
    replace openhourf_`w'_v3 = . if weather_window_coverage_`w' == 0
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
summarize openhourf_6_v3 openhourf_12_v3 openhourf_24_v3
display "NOTE: v2 uses Average open probability = 1 - Average closure frequency: 1=.28, 2=.73, 3=.87, 4=.88"
display "NOTE: v3 uses port-specific open probability = 1 - port-specific closure frequency from closure_frequency.csv"
display "=== Stage 4 complete ==="
