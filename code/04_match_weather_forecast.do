/* Stage 4: Match weather forecast data to transaction-level data.

   For each transaction, compute:
   - v1: openhourf_6_v1, openhourf_12_v1, openhourf_24_v1
   - v2: openhourf_6_v2, openhourf_12_v2, openhourf_24_v2

   Run: stata-mp < code/04_match_weather_forecast.do
*/

set more off
clear all

* ── Import transaction data (with anchor results) ──────────────
use "data_intermediate/03_transaction_with_anchor.dta", clear

* Keep only needed variables for stage 4
keep transaction_id port startdate starthour

* Drop transactions with empty port
drop if missing(port)
replace port = strtrim(port)
drop if port == ""

* Parse start datetime
gen double start_dt = clock(startdate + " " + string(starthour, "%02.0f") + ":00:00", "YMDhms")
format start_dt %tc

tempfile tx
save `tx', replace

* ── Load weather forecast data ─────────────────────────────────
use "data_raw/气象预报.dta", clear

* Ensure port is string
tostring port, replace force
replace port = strtrim(port)

* Create datetime
gen double weather_dt = clock(string(date_numeric, "%tdCCYY-NN-DD") + " " + string(hour, "%02.0f") + ":00:00", "YMDhms")
format weather_dt %tc

* Weather index variable
rename 气象指数 windex

keep port weather_dt windex
sort port weather_dt
save `tx', replace

* ═══════════════════════════════════════════════════════════════
* Port-specific closure frequency (from closure_frequency.csv)
* Open prob = 1 - closure_freq for each port-MIO combination.
* NOTE: v2 computation in Stata uses a simplified block; for full
*       port-specific v2, use the Python pipeline.
* ═══════════════════════════════════════════════════════════════

* ── Match using frame-based lookup ─────────────────────────────
use `tx', clear

gen openhourf_6_v1 = .
gen openhourf_12_v1 = .
gen openhourf_24_v1 = .
gen openhourf_6_v2 = .
gen openhourf_12_v2 = .
gen openhourf_24_v2 = .
gen weather_match_flag = 0
gen weather_window_coverage_6 = 0
gen weather_window_coverage_12 = 0
gen weather_window_coverage_24 = 0

frame create weather_data
frame weather_data: use `tx', clear

quietly {
    count
    local N = r(N)

    forvalues i = 1/`N' {
        local p = port[`i']
        local t = start_dt[`i']

        local t_m6  = `t' -  6 * 3600000
        local t_p6  = `t' +  6 * 3600000
        local t_m12 = `t' - 12 * 3600000
        local t_p12 = `t' + 12 * 3600000
        local t_m24 = `t' - 24 * 3600000
        local t_p24 = `t' + 24 * 3600000

        frame weather_data {
            count if port == "`p'"
        }
        if r(N) > 0 {
            replace weather_match_flag = 1 in `i'

            * ── Window 6 ──
            frame weather_data {
                count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6'
            }
            local tot6 = r(N)
            replace weather_window_coverage_6 = `tot6' in `i'

            if `tot6' > 0 {
                * v1: count indices >= 2
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6' & windex >= 2
                }
                replace openhourf_6_v1 = r(N) in `i'

                * v2: sum open probabilities (Average closure freq from CSV)
                * Avg open prob: idx1=0.28, idx2=0.73, idx3=0.87, idx4=0.88
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6' & windex == 1
                }
                local n1 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6' & windex == 2
                }
                local n2 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6' & windex == 3
                }
                local n3 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m6' & weather_dt <= `t_p6' & windex == 4
                }
                local n4 = r(N)
                local v2_6 = `n1' * 0.28 + `n2' * 0.73 + `n3' * 0.87 + `n4' * 0.88
                replace openhourf_6_v2 = `v2_6' in `i'
            }

            * ── Window 12 ──
            frame weather_data {
                count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12'
            }
            local tot12 = r(N)
            replace weather_window_coverage_12 = `tot12' in `i'

            if `tot12' > 0 {
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12' & windex >= 2
                }
                replace openhourf_12_v1 = r(N) in `i'

                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12' & windex == 1
                }
                local n1 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12' & windex == 2
                }
                local n2 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12' & windex == 3
                }
                local n3 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m12' & weather_dt <= `t_p12' & windex == 4
                }
                local n4 = r(N)
                local v2_12 = `n1' * 0.28 + `n2' * 0.73 + `n3' * 0.87 + `n4' * 0.88
                replace openhourf_12_v2 = `v2_12' in `i'
            }

            * ── Window 24 ──
            frame weather_data {
                count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24'
            }
            local tot24 = r(N)
            replace weather_window_coverage_24 = `tot24' in `i'

            if `tot24' > 0 {
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24' & windex >= 2
                }
                replace openhourf_24_v1 = r(N) in `i'

                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24' & windex == 1
                }
                local n1 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24' & windex == 2
                }
                local n2 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24' & windex == 3
                }
                local n3 = r(N)
                frame weather_data {
                    count if port == "`p'" & weather_dt >= `t_m24' & weather_dt <= `t_p24' & windex == 4
                }
                local n4 = r(N)
                local v2_24 = `n1' * 0.28 + `n2' * 0.73 + `n3' * 0.87 + `n4' * 0.88
                replace openhourf_24_v2 = `v2_24' in `i'
            }
        }
    }
}

drop start_dt

* ── Save ───────────────────────────────────────────────────────
save "data_intermediate/04_transaction_with_weather.dta", replace

* ── Summary ────────────────────────────────────────────────────
display _n "=== Stage 4 Summary ==="
count
display "Transactions processed: " r(N)
count if weather_match_flag == 1
display "Weather matched: " r(N)
summarize openhourf_6_v1 openhourf_12_v1 openhourf_24_v1
summarize openhourf_6_v2 openhourf_12_v2 openhourf_24_v2
display "NOTE: v2 uses Average closure freq from closure_frequency.csv"
display "      See Python pipeline for port-specific v2 values."
display "=== Stage 4 complete ==="
