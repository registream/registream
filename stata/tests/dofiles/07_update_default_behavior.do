/*==============================================================================
  Test 07: Update Default Behavior
  Tests: `registream update` (no args), `registream update package`,
         `registream update dataset` (should error with helpful message)
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
local test_dir = "`tmpbase'_update_default"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 07: Update Default Behavior"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 3

*==============================================================================
* Test 1: `registream update` (no arguments) defaults to package check
*==============================================================================

di as text "Test 1/3: registream update (no args) defaults to package update"

cap noi registream update
local rc1 = _rc

* Should run without error (rc=0) - defaults to package update check
if (`rc1' == 0) {
	di as result "  [PASS] registream update ran successfully (defaults to package)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream update failed with rc=`rc1'"
}

*==============================================================================
* Test 2: `registream update package` explicitly checks package
*==============================================================================

di as text "Test 2/3: registream update package"

cap noi registream update package
local rc2 = _rc

if (`rc2' == 0) {
	di as result "  [PASS] registream update package ran successfully"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream update package failed with rc=`rc2'"
}

*==============================================================================
* Test 3: `registream update dataset` should error with helpful message
*==============================================================================

di as text "Test 3/3: registream update dataset errors with guidance"

cap noi registream update dataset
local rc3 = _rc

* Should fail with 198 (unknown update target) and suggest autolabel
if (`rc3' == 198) {
	di as result "  [PASS] registream update dataset correctly errors (rc=198)"
	di as text "         (Directs user to autolabel for dataset updates)"
	local ++tests_passed
}
else if (`rc3' == 0) {
	di as error "  [FAIL] registream update dataset should not succeed (datasets are in autolabel)"
}
else {
	di as error "  [FAIL] Unexpected return code: `rc3' (expected 198)"
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
di as result "Test 07 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
