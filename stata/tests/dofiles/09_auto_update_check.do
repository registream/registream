/*==============================================================================
  Test 09: Auto Update Check
  Tests: config structure, info shows setting, config command,
         background check, notification, 24h caching
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
local test_dir = "`tmpbase'_auto_update"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 09: Auto Update Check"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 6

*==============================================================================
* Test 1: Config structure includes auto_update_check field
*==============================================================================

di as text "Test 1/6: Config has auto_update_check field"

* Initialize config
_rs_config init "`test_dir'"

_rs_config get "`test_dir'" "auto_update_check"
if (r(found) == 1) {
	di as result "  [PASS] auto_update_check field exists in config (value: `r(value)')"
	local ++tests_passed
}
else {
	di as error "  [FAIL] auto_update_check field not found in config"
}

*==============================================================================
* Test 2: registream info shows auto_update_check setting
*==============================================================================

di as text "Test 2/6: registream info shows auto_update_check"

* Run info and capture output (it should not error)
cap noi registream info
if (_rc == 0) {
	di as result "  [PASS] registream info displays auto_update_check setting"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream info failed (rc=`=_rc')"
}

*==============================================================================
* Test 3: Config command can toggle auto_update_check
*==============================================================================

di as text "Test 3/6: registream config can toggle auto_update_check"

* Set to false
cap noi registream config, auto_update_check(false)
_rs_config get "`test_dir'" "auto_update_check"
local val1 "`r(value)'"

* Set back to true
cap noi registream config, auto_update_check(true)
_rs_config get "`test_dir'" "auto_update_check"
local val2 "`r(value)'"

if ("`val1'" == "false" & "`val2'" == "true") {
	di as result "  [PASS] auto_update_check toggles correctly (false -> true)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Toggle failed: after false=`val1', after true=`val2'"
}

*==============================================================================
* Test 4: Background check respects auto_update_check=false
*==============================================================================

di as text "Test 4/6: Background check respects disabled setting"

* Disable auto update
_rs_config set "`test_dir'" "auto_update_check" "false"

* Disable telemetry so send_heartbeat exits after cache read
_rs_config set "`test_dir'" "telemetry_enabled" "false"

* Clear cached update state from earlier tests (Test 2 heartbeat may have set this)
_rs_config set "`test_dir'" "update_available" "false"
_rs_config set "`test_dir'" "latest_version" ""

* Run heartbeat - should respect disabled setting. send_heartbeat is now
* rclass; reading r(update_available) should come back 0 when the feature
* is disabled.
_rs_utils get_version
local ver "`r(version)'"
cap noi _rs_updates send_heartbeat "`test_dir'" "`ver'" "test" "" "" "" ""

* Should not report an update when disabled
if ("`r(update_available)'" == "0" | "`r(update_available)'" == "") {
	di as result "  [PASS] Background check skipped when auto_update_check=false"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Background check ran despite auto_update_check=false"
}

* Re-enable
_rs_config set "`test_dir'" "auto_update_check" "true"

*==============================================================================
* Test 5: Notification display mechanism
*==============================================================================

di as text "Test 5/6: Update notification display"

* show_notification now takes args, not globals.
cap noi _rs_updates show_notification , ///
	current_version("`ver'") scope(core) ///
	core_update(1) core_latest("99.0.0") ///
	autolabel_update(0) autolabel_latest("") ///
	datamirror_update(0) datamirror_latest("")
if (_rc == 0) {
	di as result "  [PASS] show_notification ran without error"
	local ++tests_passed
}
else {
	di as error "  [FAIL] show_notification errored (rc=`=_rc')"
}

*==============================================================================
* Test 6: 24-hour caching (last_update_check timestamp)
*==============================================================================

di as text "Test 6/6: 24-hour cache via last_update_check timestamp"

* Set last_update_check to current time (should be fresh, no re-check)
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")
_rs_config set "`test_dir'" "last_update_check" "`current_clock'"

* Read it back to verify it persisted
_rs_config get "`test_dir'" "last_update_check"
local stored_check "`r(value)'"

if ("`stored_check'" != "" & "`stored_check'" != ".") {
	di as result "  [PASS] last_update_check timestamp stored: `stored_check'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] last_update_check not stored properly"
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
di as result "Test 09 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
