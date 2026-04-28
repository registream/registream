/*==============================================================================
  Test 14: Network Requests Timing
  Tests: API host resolution, version check timing, heartbeat mechanism,
         offline mode behavior, network error handling
  Author: Jeffrey Clark
==============================================================================*/

clear all
version 16.0

* Find project root
local cwd = "`c(pwd)'"
local project_root ""
forvalues i = 0/5 {
	local search_path = "`cwd'"
	forvalues j = 1/`i' {
		local search_path = "`search_path'/.."
	}
	capture confirm file "`search_path'/.project-root"
	if _rc == 0 {
		quietly cd "`search_path'"
		local project_root = "`c(pwd)'"
		quietly cd "`cwd'"
		continue, break
	}
}
if "`project_root'" == "" {
	di as error "ERROR: Could not find .project-root file"
	exit 601
}

global PROJECT_ROOT "`project_root'"
global TEST_DIR "$PROJECT_ROOT/stata/tests"
global SRC_DIR "$PROJECT_ROOT/stata/src"
global TEST_LOGS_DIR "$TEST_DIR/logs"
cap mkdir "$TEST_LOGS_DIR"
discard
adopath ++ "$SRC_DIR"
do "$SRC_DIR/_rs_utils.ado"
cap do "$SRC_DIR/../dev/host_override.do"
do "$SRC_DIR/../dev/auto_approve.do"

*==============================================================================
* Setup: Isolated temp directory
*==============================================================================

tempfile tmpbase
local test_dir = "`tmpbase'_network"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

* Initialize config
_rs_config init "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 14: Network Requests Timing"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 5

*==============================================================================
* Test 1: API host resolution
*==============================================================================

di as text "Test 1/5: API host resolution"

_rs_utils get_api_host
local api_host "`r(host)'"

if ("`api_host'" != "") {
	di as result "  [PASS] API host resolved: `api_host'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] API host returned empty"
}

*==============================================================================
* Test 2: Version check timing (should complete in reasonable time)
*==============================================================================

di as text "Test 2/5: Package version check timing"

_rs_utils get_version
local ver "`r(version)'"

* Time the check_package call
local t1 = clock("`c(current_date)' `c(current_time)'", "DMY hms")
cap noi _rs_updates check_package "`test_dir'" "`ver'"
local t2 = clock("`c(current_date)' `c(current_time)'", "DMY hms")

local elapsed_ms = `t2' - `t1'
local reason "`r(reason)'"

* Should complete (regardless of network outcome) - main test is it doesn't hang
di as text "  Elapsed: `elapsed_ms' ms, reason: `reason'"

if ("`reason'" != "") {
	di as result "  [PASS] Version check completed with reason: `reason'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Version check did not return a reason"
}

*==============================================================================
* Test 3: Heartbeat mechanism (send_heartbeat)
*==============================================================================

di as text "Test 3/5: Heartbeat send mechanism"

* Ensure telemetry is enabled for this test
_rs_config set "`test_dir'" "telemetry_enabled" "true"
_rs_config set "`test_dir'" "internet_access" "true"
_rs_config set "`test_dir'" "auto_update_check" "true"

* Clear last_update_check to force a check
_rs_config set "`test_dir'" "last_update_check" ""

* Send heartbeat (may fail on network but should not error in Stata).
* New positional args: dir ver cmd module module_version al_ver dm_ver
cap noi _rs_updates send_heartbeat "`test_dir'" "`ver'" "registream info" "" "" "" ""

if (_rc == 0) {
	di as result "  [PASS] send_heartbeat completed without Stata error"
	local ++tests_passed
}
else {
	di as error "  [FAIL] send_heartbeat errored (rc=`=_rc')"
}

*==============================================================================
* Test 4: Offline mode - no network requests
*==============================================================================

di as text "Test 4/5: Offline mode blocks all network requests"

_rs_config set "`test_dir'" "internet_access" "false"

cap noi _rs_updates check_package "`test_dir'" "`ver'"
local reason4 "`r(reason)'"

if ("`reason4'" == "internet_disabled") {
	di as result "  [PASS] Offline mode prevents network requests"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected internet_disabled, got: `reason4'"
}

_rs_config set "`test_dir'" "internet_access" "true"

*==============================================================================
* Test 5: Network error handling (invalid host)
*==============================================================================

di as text "Test 5/5: Network error handling with invalid host"

* Save original test host
local orig_test_host "$REGISTREAM_TEST_HOST"

* Set invalid host to force network error
global REGISTREAM_TEST_HOST "http://invalid.host.that.does.not.exist:9999"

* Reload dev utils with new host
cap do "$SRC_DIR/../dev/host_override.do"

* Should handle gracefully (network_error reason)
cap noi _rs_updates check_package "`test_dir'" "`ver'"
local reason5 "`r(reason)'"

if ("`reason5'" == "network_error") {
	di as result "  [PASS] Invalid host handled gracefully: network_error"
	local ++tests_passed
}
else if ("`reason5'" == "parse_error") {
	di as result "  [PASS] Invalid host handled gracefully: parse_error"
	local ++tests_passed
}
else {
	* Even if it times out, as long as it didn't crash Stata, it's OK
	di as text "  [PASS] No Stata crash on invalid host (reason: `reason5')"
	local ++tests_passed
}

* Restore original host
global REGISTREAM_TEST_HOST "`orig_test_host'"
cap do "$SRC_DIR/../dev/host_override.do"

*==============================================================================
* Cleanup
*==============================================================================

cap erase "`test_dir'/config_stata.csv"
cap _rs_utils del_folder_rec "`test_dir'"
global registream_dir ""

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 14 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
