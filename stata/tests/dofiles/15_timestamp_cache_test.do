/*==============================================================================
  Test 15: Timestamp Cache Logic
  Pure arithmetic test for 24-hour timestamp caching logic
  Standalone - no project root or config dependencies
  Author: Jeffrey Clark
==============================================================================*/

clear all
version 16.0

di as result ""
di as result "============================================================"
di as result "Test 15: Timestamp Cache Logic"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 6

*==============================================================================
* Test 1: Clock function returns valid timestamp
*==============================================================================

di as text "Test 1/6: Stata clock() returns valid timestamp"

local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

if (`current_clock' > 0) {
	di as result "  [PASS] Current clock value: `current_clock'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Invalid clock value: `current_clock'"
}

*==============================================================================
* Test 2: 24-hour difference calculation
*==============================================================================

di as text "Test 2/6: 24 hours = 86,400,000 milliseconds"

local ms_per_day = 86400000
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")
local yesterday = `current_clock' - `ms_per_day'

local diff = `current_clock' - `yesterday'

if (`diff' == `ms_per_day') {
	di as result "  [PASS] 24h difference correctly computed: `diff' ms"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected `ms_per_day', got `diff'"
}

*==============================================================================
* Test 3: Cache is stale after 24 hours
*==============================================================================

di as text "Test 3/6: Cache stale detection (>= 24h)"

local ms_per_day = 86400000
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

* Simulate a check from 25 hours ago
local old_check = `current_clock' - (`ms_per_day' + 3600000)
local time_diff = `current_clock' - `old_check'

local should_check = 0
if (`time_diff' >= `ms_per_day') {
	local should_check = 1
}

if (`should_check' == 1) {
	di as result "  [PASS] 25h-old timestamp correctly marked as stale"
	local ++tests_passed
}
else {
	di as error "  [FAIL] 25h-old timestamp not detected as stale"
}

*==============================================================================
* Test 4: Cache is fresh within 24 hours
*==============================================================================

di as text "Test 4/6: Cache fresh detection (< 24h)"

local ms_per_day = 86400000
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

* Simulate a check from 1 hour ago
local recent_check = `current_clock' - 3600000
local time_diff = `current_clock' - `recent_check'

local should_check = 0
if (`time_diff' >= `ms_per_day') {
	local should_check = 1
}

if (`should_check' == 0) {
	di as result "  [PASS] 1h-old timestamp correctly marked as fresh"
	local ++tests_passed
}
else {
	di as error "  [FAIL] 1h-old timestamp incorrectly marked as stale"
}

*==============================================================================
* Test 5: Empty timestamp means always check
*==============================================================================

di as text "Test 5/6: Empty timestamp triggers check"

local last_check ""
local should_check = 0

if ("`last_check'" == "" | "`last_check'" == ".") {
	local should_check = 1
}

if (`should_check' == 1) {
	di as result "  [PASS] Empty timestamp triggers update check"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Empty timestamp did not trigger check"
}

*==============================================================================
* Test 6: Exactly 24 hours triggers check (boundary condition)
*==============================================================================

di as text "Test 6/6: Exactly 24h boundary triggers check"

local ms_per_day = 86400000
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

* Simulate a check from exactly 24 hours ago
local exact_check = `current_clock' - `ms_per_day'
local time_diff = `current_clock' - `exact_check'

local should_check = 0
if (`time_diff' >= `ms_per_day') {
	local should_check = 1
}

if (`should_check' == 1) {
	di as result "  [PASS] Exactly 24h boundary correctly triggers check"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Exactly 24h boundary did not trigger check"
}

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 15 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
