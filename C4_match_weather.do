clear all
set more off
set maxvar 10000



capture log close
log using "C4_match_weather.log", replace

di "Stage 4: Matching Weather Forecast Data"
di "=================================================="

di "Step A: Build closure frequency table from anchorage + weather data"
di "=================================================="

di "Loading weather forecast data..."
use "气象预报.dta", clear
di "  Weather observations: " _N

di "Loading anchorage data..."
merge 1:1 port date_numeric hour using "锚地开放.dta"
di "  Merge results:"
tab _merge

di "Keeping matched records only..."
keep if _merge == 3
drop _merge

di "Computing closure frequency by (port, weather_index)..."
gen is_closed = (status == "Closed")
collapse (mean) closure_freq = is_closed (count) n_obs = is_closed, by(port 气象指数)
rename 气象指数 weather_idx

di "Closure frequency table:"
list, sepby(port) noobs

di "Saving closure frequency table..."
tempfile closure_freq
save `closure_freq'

di ""
di "Step B: Match weather data to bunkering transactions"
di "=================================================="

di "Loading bunkering data with open hours..."
capture use "3_bunkering_with_openhours.dta", clear
if _rc != 0 {
    di as text "3_bunkering_with_openhours.dta not found, loading from Excel..."
    import excel "3_bunkering_final.xlsx", firstrow clear
    gen openhour_6 = .
    gen openhour_12 = .
    gen openhour_24 = .
}

di "  Observations: " _N

di "Converting startdate to Stata date..."
gen startdate_num = date(startdate, "DMY")
format startdate_num %td

di "Creating reference hours since 1960-01-01..."
gen ref_hours = 24 * startdate_num + starthour

di "Filtering to transactions with valid port..."
gen has_port = (port != "" & port != ".")
keep if has_port == 1
drop has_port

di "  Transactions with port: " _N

di "Creating row ID..."
gen row_id = _n

di "Expanding to 49 rows per transaction (offsets -24 to +24)..."
expand 49
bysort row_id: gen offset = _n - 25

di "  Total rows after expansion: " _N

di "Computing lookup date and hour..."
gen lookup_hours = ref_hours + offset
gen lookup_date = floor(lookup_hours / 24)
gen lookup_hour = mod(lookup_hours, 24)
format lookup_date %td

keep row_id transaction_id port offset lookup_date lookup_hour

di "Saving expanded bunkering data..."
tempfile expanded
save `expanded'

di "Loading weather forecast data..."
use "气象预报.dta", clear

di "  Weather forecast observations: " _N

di "Preparing weather data for merge..."
rename date_numeric lookup_date
rename hour lookup_hour
rename 气象指数 weather_idx

keep lookup_date lookup_hour port weather_idx

di "Saving weather data..."
tempfile weather
save `weather'

di "Merging expanded bunkering with weather data..."
use `expanded', clear
merge m:1 lookup_date lookup_hour port using `weather'

di "  Merge results:"
tab _merge

di "Computing V1 (threshold) open indicators..."
gen is_open_v1 = 0
replace is_open_v1 = 1 if _merge == 3 & weather_idx >= 2

di "Merging closure frequency table for V2..."
drop _merge
merge m:1 port weather_idx using `closure_freq'
di "  Closure freq merge results:"
tab _merge

di "Computing V2 (probability) open values..."
gen open_prob_v2 = 0
replace open_prob_v2 = 1 - closure_freq if !missing(closure_freq) & _merge == 3
drop _merge

di "Counting V1 open hours by window..."
bysort row_id: egen openhourf_6_v1 = total(is_open_v1 * (abs(offset) <= 6))
bysort row_id: egen openhourf_12_v1 = total(is_open_v1 * (abs(offset) <= 12))
bysort row_id: egen openhourf_24_v1 = total(is_open_v1 * (abs(offset) <= 24))

di "Summing V2 open probabilities by window..."
bysort row_id: egen openhourf_6_v2 = total(open_prob_v2 * (abs(offset) <= 6))
bysort row_id: egen openhourf_12_v2 = total(open_prob_v2 * (abs(offset) <= 12))
bysort row_id: egen openhourf_24_v2 = total(open_prob_v2 * (abs(offset) <= 24))

di "Collapsing back to transaction level..."
keep row_id transaction_id openhourf_6_v1 openhourf_12_v1 openhourf_24_v1 ///
     openhourf_6_v2 openhourf_12_v2 openhourf_24_v2
bysort row_id: keep if _n == 1
drop row_id

di "  Transactions with weather data: " _N

di "Saving weather match data..."
tempfile weather_match
save `weather_match'

di "Merging weather data back to bunkering data..."
capture use "3_bunkering_with_openhours.dta", clear
if _rc != 0 {
    import excel "3_bunkering_final.xlsx", firstrow clear
    gen openhour_6 = .
    gen openhour_12 = .
    gen openhour_24 = .
}

merge 1:1 transaction_id using `weather_match'
drop _merge

replace openhourf_6_v1 = 0 if openhourf_6_v1 == . & port != "" & port != "."
replace openhourf_12_v1 = 0 if openhourf_12_v1 == . & port != "" & port != "."
replace openhourf_24_v1 = 0 if openhourf_24_v1 == . & port != "" & port != "."
replace openhourf_6_v2 = 0 if openhourf_6_v2 == . & port != "" & port != "."
replace openhourf_12_v2 = 0 if openhourf_12_v2 == . & port != "" & port != "."
replace openhourf_24_v2 = 0 if openhourf_24_v2 == . & port != "" & port != "."

di "Summary of weather forecast open hours (V1 threshold):"
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1

di "Summary of weather forecast open hours (V2 probability):"
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2

di "Saving final result..."
save "4_bunkering_matched.dta", replace
export excel "4_bunkering_matched.xlsx", firstrow(variables) replace

di "Stage 4 (Weather matching) complete!"
di "Final output: 4_bunkering_matched.xlsx"
log close
