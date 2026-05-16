clear all
set more off
set maxvar 10000

capture log close
log using "C3_external_match.log", replace

di "Stage 3: External Data Matching"
di "=================================================="
di "Matching anchorage open status + weather forecast to bunkering transactions"

* ============================================================
* Step A: Build closure frequency table (anchorage + weather)
* ============================================================
di ""
di "Step A: Building closure frequency table..."
use "气象预报.dta", clear
merge 1:1 port date_numeric hour using "锚地开放.dta"
di "  Weather + anchorage merge:"
tab _merge
keep if _merge == 3
drop _merge
gen is_closed = (status == "Closed")
collapse (mean) closure_freq = is_closed (count) n_obs = is_closed, by(port 气象指数)
rename 气象指数 weather_idx
di "Closure frequency by (port, weather_idx):"
list, sepby(port) noobs
tempfile closure_freq
save `closure_freq'

* ============================================================
* Step B: Expand bunkering data (shared expansion, done once)
* ============================================================
di ""
di "Step B: Loading and expanding bunkering data..."
import excel "3_bunkering_final.xlsx", firstrow clear
di "  Transactions: " _N

gen startdate_num = date(startdate, "DMY")
format startdate_num %td
drop if missing(startdate_num)

gen ref_hours = 24 * startdate_num + starthour

gen has_port = (port != "" & port != ".")
keep if has_port == 1
drop has_port
di "  Transactions with valid port: " _N

gen row_id = _n
expand 49
bysort row_id: gen offset = _n - 25
di "  Rows after expansion: " _N

gen lookup_hours = ref_hours + offset
gen lookup_date = floor(lookup_hours / 24)
gen lookup_hour = mod(lookup_hours, 24)
format lookup_date %td

keep row_id transaction_id port offset lookup_date lookup_hour
tempfile expanded
save `expanded'

* ============================================================
* Step C: Match anchorage open data
* ============================================================
di ""
di "Step C: Matching anchorage open data..."
use "锚地开放.dta", clear
di "  Anchorage observations: " _N
rename date_numeric lookup_date
rename hour lookup_hour
capture confirm string variable port
if _rc != 0 {
    destring port, replace
}
keep lookup_date lookup_hour port status
tempfile anchorage
save `anchorage'

use `expanded', clear
merge m:1 lookup_date lookup_hour port using `anchorage'
di "  Anchorage merge:"
tab _merge
gen is_open = (_merge == 3 & status == "Open")
drop _merge status
tempfile expanded_anch
save `expanded_anch'

* ============================================================
* Step D: Match weather forecast data
* ============================================================
di ""
di "Step D: Matching weather forecast data..."
use "气象预报.dta", clear
rename date_numeric lookup_date
rename hour lookup_hour
rename 气象指数 weather_idx
keep lookup_date lookup_hour port weather_idx
tempfile weather
save `weather'

use `expanded_anch', clear
merge m:1 lookup_date lookup_hour port using `weather'
di "  Weather merge:"
tab _merge
gen has_weather = (_merge == 3)
gen is_open_v1 = (_merge == 3 & weather_idx >= 2)
drop _merge
save `expanded_anch', replace

* Merge closure frequency for V2 computation
merge m:1 port weather_idx using `closure_freq'
di "  Closure freq merge:"
tab _merge
di "  Observations with weather info (any merge type): " _N
gen open_prob_v2 = 1 - closure_freq if !missing(closure_freq) & has_weather
drop _merge closure_freq n_obs has_weather

* ============================================================
* Step E: Compute open hour variables
* ============================================================
di ""
di "Step E: Computing open hour variables..."

bysort row_id: egen openhour_6 = total(is_open * (abs(offset) <= 6))
bysort row_id: egen openhour_12 = total(is_open * (abs(offset) <= 12))
bysort row_id: egen openhour_24 = total(is_open * (abs(offset) <= 24))

bysort row_id: egen openhourf_6_v1 = total(is_open_v1 * (abs(offset) <= 6))
bysort row_id: egen openhourf_12_v1 = total(is_open_v1 * (abs(offset) <= 12))
bysort row_id: egen openhourf_24_v1 = total(is_open_v1 * (abs(offset) <= 24))

bysort row_id: egen openhourf_6_v2 = total(open_prob_v2 * (abs(offset) <= 6))
bysort row_id: egen openhourf_12_v2 = total(open_prob_v2 * (abs(offset) <= 12))
bysort row_id: egen openhourf_24_v2 = total(open_prob_v2 * (abs(offset) <= 24))

di "Collapsing back to transaction level..."
keep row_id transaction_id openhour_6 openhour_12 openhour_24 ///
    openhourf_6_v1 openhourf_12_v1 openhourf_24_v1 ///
    openhourf_6_v2 openhourf_12_v2 openhourf_24_v2
bysort row_id: keep if _n == 1
drop row_id
di "  Transactions with match data: " _N

tempfile match_vars
save `match_vars'

* ============================================================
* Step F: Merge back to bunkering data and save
* ============================================================
di ""
di "Step F: Merging results back to bunkering data..."
import excel "3_bunkering_final.xlsx", firstrow clear
merge 1:1 transaction_id using `match_vars'
di "  Final merge:"
tab _merge
drop _merge

* Fill missing values with 0 for valid-port transactions
foreach var in openhour_6 openhour_12 openhour_24 ///
    openhourf_6_v1 openhourf_12_v1 openhourf_24_v1 ///
    openhourf_6_v2 openhourf_12_v2 openhourf_24_v2 {
    replace `var' = 0 if missing(`var') & port != "" & port != "."
}

di ""
di "Summary — Anchorage open hours:"
summarize openhour_6 openhour_12 openhour_24

di ""
di "Summary — Weather forecast (V1 threshold):"
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1

di ""
di "Summary — Weather forecast (V2 probability):"
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2

save "4_bunkering_matched.dta", replace
export excel "4_bunkering_matched.xlsx", firstrow(variables) replace

di ""
di "Stage 3 complete!"
di "Output: 4_bunkering_matched.dta / 4_bunkering_matched.xlsx"
log close
