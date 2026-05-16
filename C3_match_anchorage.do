clear all
set more off
set maxvar 10000



capture log close
log using "C3_match_anchorage.log", replace

di "Stage 3: Matching Anchorage Open Data"
di "=================================================="

capture confirm file "锚地开放.dta"
if _rc != 0 {
    di as error "锚地开放.dta not found in working directory!"
    di as text "Creating openhour variables with missing values..."

    import excel "3_bunkering_final.xlsx", firstrow clear

    gen openhour_6 = .
    gen openhour_12 = .
    gen openhour_24 = .

    save "3_bunkering_with_openhours.dta", replace
    export excel "3_bunkering_with_openhours.xlsx", firstrow(variables) replace

    di as text "Stage 3 skipped - 锚地开放.dta not available"
    log close
    exit
}

di "Loading bunkering final data..."
import excel "3_bunkering_final.xlsx", firstrow clear

di "  Observations: " _N
di "  Variables: " c(k)

di "Converting startdate to Stata date..."
gen startdate_num = date(startdate, "DMY")
format startdate_num %td
drop if missing(startdate_num)

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

di "Loading 锚地开放.dta..."
use "锚地开放.dta", clear

di "  Anchorage observations: " _N

di "Preparing anchorage data for merge..."
rename date_numeric lookup_date
rename hour lookup_hour

capture confirm string variable port
if _rc != 0 {
    destring port, replace
}

keep lookup_date lookup_hour port status

di "Saving anchorage data..."
tempfile anchorage
save `anchorage'

di "Merging expanded bunkering with anchorage data..."
use `expanded', clear
merge m:1 lookup_date lookup_hour port using `anchorage'

di "  Merge results:"
tab _merge

di "Computing open hour indicators..."
gen is_open = 0
replace is_open = 1 if _merge == 3 & status == "Open"

di "Counting open hours by window..."
bysort row_id: egen openhour_6 = total(is_open * (abs(offset) <= 6))
bysort row_id: egen openhour_12 = total(is_open * (abs(offset) <= 12))
bysort row_id: egen openhour_24 = total(is_open * (abs(offset) <= 24))

di "Collapsing back to transaction level..."
keep row_id transaction_id openhour_6 openhour_12 openhour_24
bysort row_id: keep if _n == 1
drop row_id

di "  Transactions with open hours: " _N

di "Saving open hours data..."
tempfile openhours
save `openhours'

di "Merging open hours back to bunkering data..."
import excel "3_bunkering_final.xlsx", firstrow clear

merge 1:1 transaction_id using `openhours'
drop _merge

replace openhour_6 = 0 if openhour_6 == . & port != "" & port != "."
replace openhour_12 = 0 if openhour_12 == . & port != "" & port != "."
replace openhour_24 = 0 if openhour_24 == . & port != "" & port != "."

di "Summary of open hours:"
summarize openhour_6 openhour_12 openhour_24

di "Saving intermediate result..."
save "3_bunkering_with_openhours.dta", replace
export excel "3_bunkering_with_openhours.xlsx", firstrow(variables) replace

di "Stage 3 (Anchorage matching) complete!"
log close
