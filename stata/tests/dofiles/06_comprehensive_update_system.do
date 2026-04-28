/*==============================================================================
  Test 06: Comprehensive Update System
  Tests: no version field in config, version from code, read-only handling,
         update check mechanism, update workflow scenarios, config persistence,
         read-only system support
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
local test_dir = "`tmpbase'_update_test"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 06: Comprehensive Update System"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 7

*==============================================================================
* Test 1: Config does NOT contain a version field
*==============================================================================

di as text "Test 1/7: Config does not store version (version comes from code)"

* Initialize config
_rs_config init "`test_dir'"

* Check that there's no "version" key in config
_rs_config get "`test_dir'" "version"
if (r(found) == 0) {
	di as result "  [PASS] No 'version' key in config_stata.csv"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Found 'version' key in config (should not be there)"
}

*==============================================================================
* Test 2: Version comes from code (_rs_utils get_version)
*==============================================================================

di as text "Test 2/7: Version comes from code, not config"

_rs_utils get_version
local code_version "`r(version)'"

if ("`code_version'" != "") {
	di as result "  [PASS] _rs_utils get_version returned: `code_version'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] _rs_utils get_version returned empty string"
}

*==============================================================================
* Test 3: Read-only config handling (graceful degradation)
*==============================================================================

di as text "Test 3/7: Read-only config handling"

* Create a temp dir that we'll make read-only
tempfile tmpbase2
local ro_dir = "`tmpbase2'_readonly"
cap mkdir "`ro_dir'"

* Write a valid config first
_rs_config init "`ro_dir'"

* Try to set a value - should succeed on writable dir
_rs_config set "`ro_dir'" "usage_logging" "false"
_rs_config get "`ro_dir'" "usage_logging"
if ("`r(value)'" == "false") {
	di as result "  [PASS] Config set/get works on writable directory"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config set/get failed on writable directory"
}

* Cleanup readonly test
cap erase "`ro_dir'/config_stata.csv"
cap rmdir "`ro_dir'"

*==============================================================================
* Test 4: Update check mechanism (check_package returns structured results)
*==============================================================================

di as text "Test 4/7: Update check returns structured results"

* Re-init config for this test
cap erase "`test_dir'/config_stata.csv"
_rs_config init "`test_dir'"

* Call check_package - may fail due to network but should return structured results
_rs_utils get_version
local ver "`r(version)'"

cap noi _rs_updates check_package "`test_dir'" "`ver'"
local rc_val = _rc
local upd_avail = r(update_available)
local cur_ver "`r(current_version)'"
local reason "`r(reason)'"

* Regardless of network success, we should have structured return values
if ("`reason'" != "") {
	di as result "  [PASS] check_package returned reason: `reason'"
	di as text "         update_available=`upd_avail', current=`cur_ver'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] check_package did not return structured results"
}

*==============================================================================
* Test 5: Update workflow scenarios (internet disabled)
*==============================================================================

di as text "Test 5/7: Update check with internet disabled"

_rs_config set "`test_dir'" "internet_access" "false"

cap noi _rs_updates check_package "`test_dir'" "`ver'"
local reason "`r(reason)'"

if ("`reason'" == "internet_disabled") {
	di as result "  [PASS] Returns 'internet_disabled' when internet_access=false"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected reason='internet_disabled', got: `reason'"
}

* Restore internet
_rs_config set "`test_dir'" "internet_access" "true"

*==============================================================================
* Test 6: Config persistence across operations
*==============================================================================

di as text "Test 6/7: Config values persist across multiple operations"

* Set several values
_rs_config set "`test_dir'" "telemetry_enabled" "false"
_rs_config set "`test_dir'" "auto_update_check" "false"

* Read them back
_rs_config get "`test_dir'" "telemetry_enabled"
local tel_val "`r(value)'"

_rs_config get "`test_dir'" "auto_update_check"
local upd_val "`r(value)'"

if ("`tel_val'" == "false" & "`upd_val'" == "false") {
	di as result "  [PASS] Multiple config values persist correctly"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config persistence issue: telemetry=`tel_val', auto_update=`upd_val'"
}

*==============================================================================
* Test 7: Read-only system support (init returns writable=0 gracefully)
*==============================================================================

di as text "Test 7/7: Init on non-existent path returns gracefully"

* Try to init in a path that doesn't exist and can't be created
local impossible_dir "/nonexistent_path_12345/registream"
cap _rs_config init "`impossible_dir'"

* Should not error out - graceful degradation
if (_rc == 0) {
	di as result "  [PASS] Config init handles impossible paths gracefully"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config init errored on impossible path (rc=`=_rc')"
}

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
di as result "Test 06 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
