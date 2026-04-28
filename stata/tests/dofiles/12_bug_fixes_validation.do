/*==============================================================================
  Test 12: Bug Fixes Validation
  Validates critical bug fixes ported from the monorepo test suite
  Author: Jeffrey Clark

  Tests:
  1. escape_ascii return local syntax (no = sign errors)
  2. registream stats doesn't log itself (no recursion)
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

* Get registream directory
_rs_utils get_dir
local registream_dir "`r(dir)'"

di as result ""
di as result "============================================================"
di as result "Test 12: Bug Fixes Validation"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 5

*==============================================================================
* Test 1a: escape_ascii with period
*==============================================================================

di as text "Test 1/5: escape_ascii returns correct value for '.'"

_rs_utils escape_ascii "test.value"
local escaped1 "`r(escaped_string)'"

if ("`escaped1'" == "testq46value") {
	di as result "  [PASS] escape_ascii('.') = testq46value"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected 'testq46value', got '`escaped1'"
}

*==============================================================================
* Test 1b: escape_ascii with asterisk
*==============================================================================

di as text "Test 2/5: escape_ascii returns correct value for '*'"

_rs_utils escape_ascii "test*value"
local escaped2 "`r(escaped_string)'"

if ("`escaped2'" == "testq42value") {
	di as result "  [PASS] escape_ascii('*') = testq42value"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected 'testq42value', got '`escaped2'"
}

*==============================================================================
* Test 1c: escape_ascii with space
*==============================================================================

di as text "Test 3/5: escape_ascii returns correct value for ' '"

_rs_utils escape_ascii "test value"
local escaped3 "`r(escaped_string)'"

if ("`escaped3'" == "testq32value") {
	di as result "  [PASS] escape_ascii(' ') = testq32value"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected 'testq32value', got '`escaped3'"
}

*==============================================================================
* Test 2a: registream stats runs without error
*==============================================================================

di as text "Test 4/5: registream stats runs successfully"

* Initialize config so registream commands work
_rs_config init "`registream_dir'"

cap noi registream stats

if (_rc == 0) {
	di as result "  [PASS] registream stats ran successfully"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream stats failed with rc=`=_rc'"
}

*==============================================================================
* Test 2b: registream stats doesn't log itself (no recursion)
*==============================================================================

di as text "Test 5/5: registream stats does not log itself"

local usage_file "`registream_dir'/usage_stata.csv"
cap confirm file "`usage_file'"
if (_rc == 0) {
	* Count lines before
	tempname fh
	file open `fh' using "`usage_file'", read
	local lines_before = 0
	file read `fh' line
	while r(eof)==0 {
		local ++lines_before
		file read `fh' line
	}
	file close `fh'

	di as text "  Lines in usage_stata.csv before stats: `lines_before'"
}
else {
	local lines_before = 0
	di as text "  usage_stata.csv doesn't exist yet"
}

* Run registream stats (should NOT add a line)
cap noi registream stats

* Count lines after
cap confirm file "`usage_file'"
if (_rc == 0) {
	tempname fh
	file open `fh' using "`usage_file'", read
	local lines_after = 0
	file read `fh' line
	while r(eof)==0 {
		local ++lines_after
		file read `fh' line
	}
	file close `fh'

	di as text "  Lines in usage_stata.csv after stats: `lines_after'"

	if (`lines_after' == `lines_before') {
		di as result "  [PASS] registream stats did not log itself (no recursion)"
		local ++tests_passed
	}
	else {
		di as error "  [FAIL] Line count increased from `lines_before' to `lines_after'"
	}
}
else {
	di as text "  usage_stata.csv still doesn't exist (no logging configured)"
	di as result "  [PASS] No recursion (file not created)"
	local ++tests_passed
}

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 12 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
