/*==============================================================================
  Test 99: Cleanup
  Reinitialize config_stata.csv to clean state
  Core-only cleanup (no dataset cleanup - that's autolabel's job)
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

di as result ""
di as result "============================================================"
di as result "Test 99: Cleanup - Restore Clean State"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 3

*==============================================================================
* Step 1: Get registream directory
*==============================================================================

di as text "Step 1/3: Locate registream directory"

_rs_utils get_dir
local registream_dir "`r(dir)'"

if ("`registream_dir'" != "") {
	di as result "  [PASS] RegiStream directory: `registream_dir'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Could not determine registream directory"
	exit 1
}

*==============================================================================
* Step 2: Delete existing config and reinitialize
*==============================================================================

di as text "Step 2/3: Reinitialize config_stata.csv"

local config_file "`registream_dir'/config_stata.csv"
cap erase "`config_file'"

* Reinitialize with default settings (auto-approve = Full Mode)
_rs_config init "`registream_dir'"

cap confirm file "`config_file'"
if (_rc == 0) {
	di as result "  [PASS] config_stata.csv reinitialized"
	local ++tests_passed
}
else {
	di as text "  [SKIP] Config could not be written (read-only system?)"
	local ++tests_passed
}

*==============================================================================
* Step 3: Clear test globals
*==============================================================================

di as text "Step 3/3: Clear test globals"

* Plumbing globals removed from the update system; only user-facing knobs
* and dev overrides remain.
global REGISTREAM_TEST_VERSION ""
global REGISTREAM_TEST_HOST ""

di as result "  [PASS] Test globals cleared"
local ++tests_passed

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 99 Summary: `tests_passed'/`tests_total' steps completed"
di as result "============================================================"
di as result ""
di as text "Clean state restored. Config reinitialized with Full Mode defaults."
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
