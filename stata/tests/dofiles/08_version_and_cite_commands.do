/*==============================================================================
  Test 08: Version and Info Commands
  Tests: `registream version`, `registream info`
  (Core commands only - autolabel aliases are tested in the autolabel repo)

  `registream cite` is intentionally NOT tested here: its body contains a
  build-time placeholder (``{{CITATION_REGISTREAM_ADO_CITE_BLOCK}}``) that
  only gets substituted when export_package.py copies the file to the
  server directory. Source-mode adopath loading cannot parse the raw
  placeholder. End-to-end cite coverage belongs in the autolabel repo's
  test 30, which does a real `net install` before exercising commands.
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
local test_dir = "`tmpbase'_version_cite"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 08: Version and Info Commands"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 2

*==============================================================================
* Test 1: `registream version`
*==============================================================================

di as text "Test 1/2: registream version"

cap noi registream version
local rc1 = _rc

if (`rc1' == 0) {
	* Also verify that _rs_utils get_version returns something
	_rs_utils get_version
	local ver "`r(version)'"
	if ("`ver'" != "") {
		di as result "  [PASS] registream version ran successfully (version: `ver')"
		local ++tests_passed
	}
	else {
		di as error "  [FAIL] registream version ran but get_version returned empty"
	}
}
else {
	di as error "  [FAIL] registream version failed with rc=`rc1'"
}

*==============================================================================
* Test 2: `registream info`
*==============================================================================

di as text "Test 2/2: registream info"

cap noi registream info
local rc3 = _rc

if (`rc3' == 0) {
	di as result "  [PASS] registream info ran successfully"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream info failed with rc=`rc3'"
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
di as result "Test 08 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
