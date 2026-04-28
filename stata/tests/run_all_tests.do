/*==============================================================================
  RegiStream Core - Master Test Suite

  Purpose: Run all core infrastructure verification tests
  Author: Jeffrey Clark

  Test Files:
  1. dofiles/01_config_initialization.do - Config auto-creation and defaults
  2. dofiles/06_comprehensive_update_system.do - Version & update system
  3. dofiles/07_update_default_behavior.do - Default update behavior
  4. dofiles/08_version_and_cite_commands.do - Version/info commands (cite is build-only)
  5. dofiles/09_auto_update_check.do - Auto-update check feature
  6. dofiles/10_update_notification.do - Update notification
  7. dofiles/11_telemetry_config.do - Telemetry and config system
  8. dofiles/12_bug_fixes_validation.do - escape_ascii syntax & stats recursion
  9. dofiles/13_version_resolution_priority.do - Version resolution (2-level)
  10. dofiles/14_network_requests_timing.do - Network request timing
  11. dofiles/15_timestamp_cache_test.do - Timestamp cache logic
  12. dofiles/99_cleanup.do - Clean state restoration

  Usage:
    From repo root: do stata/tests/run_all_tests.do

  Requirements:
    - API server running at localhost:5000
    - .project-root file in repo root
==============================================================================*/

clear all
version 16.0

*==============================================================================
* Find project root
*==============================================================================

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

* Create logs directory
cap mkdir "$TEST_LOGS_DIR"

*==============================================================================
* Display test suite info
*==============================================================================

di as result ""
di as result "============================================================"
di as result "RegiStream Core - Master Test Suite"
di as result "============================================================"
di as result ""
di as text "Project root: $PROJECT_ROOT"
di as text "Test directory: $TEST_DIR"
di as text ""

*==============================================================================
* Track test results
*==============================================================================

local tests_total = 0
local tests_passed = 0
local tests_failed = 0

*==============================================================================
* Run each test sequentially
*==============================================================================

* Test 1: Config Initialization
di as result "============================================================"
di as result "Test 1/12: Config Auto-Initialization"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/01_config_initialization.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 1"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 1 (rc=`=_rc')"
}

* Test 2: Comprehensive Update System
di as result "============================================================"
di as result "Test 2/12: Version & Update System"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/06_comprehensive_update_system.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 2"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 2 (rc=`=_rc')"
}

* Test 3: Update Default Behavior
di as result "============================================================"
di as result "Test 3/12: Update Default Behavior"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/07_update_default_behavior.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 3"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 3 (rc=`=_rc')"
}

* Test 4: Version and Info Commands
di as result "============================================================"
di as result "Test 4/12: Version & Info Commands"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/08_version_and_cite_commands.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 4"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 4 (rc=`=_rc')"
}

* Test 5: Auto Update Check
di as result "============================================================"
di as result "Test 5/12: Auto Update Check"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/09_auto_update_check.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 5"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 5 (rc=`=_rc')"
}

* Test 6: Update Notification
di as result "============================================================"
di as result "Test 6/12: Update Notification"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/10_update_notification.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 6"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 6 (rc=`=_rc')"
}

* Test 7: Telemetry and Config System
di as result "============================================================"
di as result "Test 7/12: Telemetry and Config System"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/11_telemetry_config.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 7"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 7 (rc=`=_rc')"
}

* Test 8: Bug Fixes Validation
di as result "============================================================"
di as result "Test 8/12: Bug Fixes Validation"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/12_bug_fixes_validation.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 8"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 8 (rc=`=_rc')"
}

* Test 9: Version Resolution Priority
di as result "============================================================"
di as result "Test 9/12: Version Resolution Priority"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/13_version_resolution_priority.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 9"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 9 (rc=`=_rc')"
}

* Test 10: Network Requests Timing
di as result "============================================================"
di as result "Test 10/12: Network Request Timing"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/14_network_requests_timing.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 10"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 10 (rc=`=_rc')"
}

* Test 11: Timestamp Cache Logic
di as result "============================================================"
di as result "Test 11/12: Timestamp Cache Logic"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/15_timestamp_cache_test.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 11"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 11 (rc=`=_rc')"
}

* Test 12: Cleanup
di as result "============================================================"
di as result "Test 12/12: Clean State Restoration"
di as result "============================================================"
local ++tests_total
cap noi do "$TEST_DIR/dofiles/99_cleanup.do"
if (_rc == 0) {
	local ++tests_passed
	di as result "[PASS] Test 12"
}
else {
	local ++tests_failed
	di as error "[FAIL] Test 12 (rc=`=_rc')"
}

*==============================================================================
* Final Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test Suite Summary"
di as result "============================================================"
di as result ""

local pass_rate = round((`tests_passed' / `tests_total') * 100)

di as result "Total Tests:  `tests_total'"
di as result "Passed:       {result:`tests_passed'}"
if (`tests_failed' > 0) {
	di as error "Failed:       {error:`tests_failed'}"
}
else {
	di as result "Failed:       `tests_failed'"
}
di as result "Pass Rate:    `pass_rate'%"
di as result ""

if (`tests_failed' == 0) {
	di as result "============================================================"
	di as result "[SUCCESS] ALL TESTS PASSED!"
	di as result "============================================================"
	di as result ""
}
else {
	di as error "============================================================"
	di as error "[FAILURE] SOME TESTS FAILED"
	di as error "============================================================"
	di as error ""
	di as text "Check individual test logs in:"
	di as text "  $TEST_LOGS_DIR"
	di as text ""
}

* Exit with error if any tests failed
if (`tests_failed' > 0) {
	exit 1
}
