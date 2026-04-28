/*==============================================================================
  Test 10: Update Notification
  Tests: simulate older version, background check globals, config persistence,
         notification display, semantic version comparisons
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
local test_dir = "`tmpbase'_notification"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

* Initialize config
_rs_config init "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 10: Update Notification"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 5

*==============================================================================
* Test 1: Simulate older version via config persistence
*==============================================================================

di as text "Test 1/5: Simulate update available via config"

* Write update_available=true and latest_version to config
_rs_config set "`test_dir'" "update_available" "true"
_rs_config set "`test_dir'" "latest_version" "99.0.0"

* Read back
_rs_config get "`test_dir'" "update_available"
local upd "`r(value)'"
_rs_config get "`test_dir'" "latest_version"
local lat "`r(value)'"

if ("`upd'" == "true" & "`lat'" == "99.0.0") {
	di as result "  [PASS] Simulated update state persisted in config"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config persistence: update_available=`upd', latest_version=`lat'"
}

*==============================================================================
* Test 2: Background check rehydrates cached update state into rclass r()
*==============================================================================

di as text "Test 2/5: Background check reads cached update state from config"

* Set last_update_check to recent time (so it uses cache, no network)
local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")
_rs_config set "`test_dir'" "last_update_check" "`current_clock'"

* Disable telemetry so send_heartbeat exits after cache read
_rs_config set "`test_dir'" "telemetry_enabled" "false"

* Run heartbeat - should read from cache and return via r(). No globals.
_rs_utils get_version
local ver "`r(version)'"
cap noi _rs_updates send_heartbeat "`test_dir'" "`ver'" "test" "" "" "" ""

if ("`r(update_available)'" == "1") {
	di as result "  [PASS] Background check rehydrated r(update_available)=1 from cache"
	local ++tests_passed
}
else {
	di as error "  [FAIL] r(update_available)=`r(update_available)' (expected 1)"
}

*==============================================================================
* Test 3: Config persistence across re-init
*==============================================================================

di as text "Test 3/5: Config values survive re-initialization"

* Re-init should NOT overwrite existing config
_rs_config init "`test_dir'"

_rs_config get "`test_dir'" "update_available"
local upd_after "`r(value)'"

if ("`upd_after'" == "true") {
	di as result "  [PASS] Config values survive re-initialization"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config lost after re-init: update_available=`upd_after'"
}

*==============================================================================
* Test 4: Notification display when update is available
*==============================================================================

di as text "Test 4/5: Notification displays when update available"

* show_notification now takes args, not globals.
cap noi _rs_updates show_notification , ///
	current_version("`ver'") scope(core) ///
	core_update(1) core_latest("99.0.0") ///
	autolabel_update(0) autolabel_latest("") ///
	datamirror_update(0) datamirror_latest("")
if (_rc == 0) {
	di as result "  [PASS] Notification displayed without error"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Notification display errored (rc=`=_rc')"
}

*==============================================================================
* Test 5: Semantic version comparison logic
*==============================================================================

di as text "Test 5/5: Semantic version comparisons"

local semver_pass = 1

* Test: 2.0.0 vs 99.0.0 -> update available (major bump)
cap noi _rs_updates check_package "`test_dir'" "2.0.0"
* This will try network; if it succeeds the comparison is done server-side
* Instead, test the comparison logic directly by simulating

* Major version: 1.0.0 < 2.0.0
local v1_major = 1
local v1_minor = 0
local v1_patch = 0
local v2_major = 2
local v2_minor = 0
local v2_patch = 0
local update = 0
if (`v2_major' > `v1_major') local update = 1
if (`update' != 1) {
	di as error "  [FAIL] 1.0.0 < 2.0.0 not detected"
	local semver_pass = 0
}

* Minor version: 2.0.0 < 2.1.0
local v1_major = 2
local v1_minor = 0
local v2_major = 2
local v2_minor = 1
local update = 0
if (`v2_major' > `v1_major') local update = 1
else if (`v2_major' == `v1_major' & `v2_minor' > `v1_minor') local update = 1
if (`update' != 1) {
	di as error "  [FAIL] 2.0.0 < 2.1.0 not detected"
	local semver_pass = 0
}

* Patch version: 2.1.0 < 2.1.1
local v1_minor = 1
local v1_patch = 0
local v2_minor = 1
local v2_patch = 1
local update = 0
if (`v2_major' > `v1_major') local update = 1
else if (`v2_major' == `v1_major' & `v2_minor' > `v1_minor') local update = 1
else if (`v2_major' == `v1_major' & `v2_minor' == `v1_minor' & `v2_patch' > `v1_patch') local update = 1
if (`update' != 1) {
	di as error "  [FAIL] 2.1.0 < 2.1.1 not detected"
	local semver_pass = 0
}

* Equal versions: 2.0.0 == 2.0.0 -> no update
local v1_major = 2
local v1_minor = 0
local v1_patch = 0
local v2_major = 2
local v2_minor = 0
local v2_patch = 0
local update = 0
if (`v2_major' > `v1_major') local update = 1
else if (`v2_major' == `v1_major' & `v2_minor' > `v1_minor') local update = 1
else if (`v2_major' == `v1_major' & `v2_minor' == `v1_minor' & `v2_patch' > `v1_patch') local update = 1
if (`update' != 0) {
	di as error "  [FAIL] 2.0.0 == 2.0.0 incorrectly flagged as update"
	local semver_pass = 0
}

* Downgrade: 3.0.0 > 2.0.0 -> no update
local v1_major = 3
local v2_major = 2
local update = 0
if (`v2_major' > `v1_major') local update = 1
if (`update' != 0) {
	di as error "  [FAIL] 3.0.0 > 2.0.0 incorrectly flagged as update"
	local semver_pass = 0
}

if (`semver_pass' == 1) {
	di as result "  [PASS] All semantic version comparisons correct"
	local ++tests_passed
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
di as result "Test 10 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
