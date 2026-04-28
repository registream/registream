/*==============================================================================
  Test 01: Config Initialization
  Tests that config_stata.csv is auto-created with correct defaults
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
* Setup: Use isolated temp directory for config testing
*==============================================================================

tempfile tmpbase
local test_dir = "`tmpbase'_config_test"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 01: Config Initialization"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 6

*==============================================================================
* Test 1: Delete config_stata.csv, verify gone
*==============================================================================

di as text "Test 1/6: Delete config_stata.csv and verify removal"

local config_file "`test_dir'/config_stata.csv"
cap erase "`config_file'"
cap confirm file "`config_file'"
if (_rc != 0) {
	di as result "  [PASS] config_stata.csv does not exist"
	local ++tests_passed
}
else {
	di as error "  [FAIL] config_stata.csv still exists after deletion"
}

*==============================================================================
* Test 2: Run `registream info` to trigger config init
*==============================================================================

di as text "Test 2/6: Run registream info (triggers config init)"

cap noi registream info
if (_rc == 0) {
	di as result "  [PASS] registream info ran successfully"
	local ++tests_passed
}
else {
	di as error "  [FAIL] registream info failed with rc=`=_rc'"
}

*==============================================================================
* Test 3: Verify config_stata.csv was created
*==============================================================================

di as text "Test 3/6: Verify config_stata.csv was created"

cap confirm file "`config_file'"
if (_rc == 0) {
	di as result "  [PASS] config_stata.csv exists after registream info"
	local ++tests_passed
}
else {
	di as error "  [FAIL] config_stata.csv was not created"
}

*==============================================================================
* Test 4: Check defaults (auto-approve mode = Full Mode defaults)
*==============================================================================

di as text "Test 4/6: Check default values in config"

local test4_pass = 1

_rs_config get "`test_dir'" "usage_logging"
if ("`r(value)'" == "true") {
	di as result "  [OK] usage_logging = true"
}
else {
	di as error "  [FAIL] usage_logging = `r(value)' (expected true)"
	local test4_pass = 0
}

_rs_config get "`test_dir'" "telemetry_enabled"
if ("`r(value)'" == "true") {
	di as result "  [OK] telemetry_enabled = true"
}
else {
	di as error "  [FAIL] telemetry_enabled = `r(value)' (expected true)"
	local test4_pass = 0
}

_rs_config get "`test_dir'" "internet_access"
if ("`r(value)'" == "true") {
	di as result "  [OK] internet_access = true"
}
else {
	di as error "  [FAIL] internet_access = `r(value)' (expected true)"
	local test4_pass = 0
}

if (`test4_pass' == 1) {
	di as result "  [PASS] All defaults correct"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Some defaults incorrect"
}

*==============================================================================
* Test 5: Modify and verify persistence
*==============================================================================

di as text "Test 5/6: Modify config and verify persistence"

_rs_config set "`test_dir'" "usage_logging" "false"
_rs_config get "`test_dir'" "usage_logging"
if ("`r(value)'" == "false") {
	di as result "  [PASS] Config modification persisted (usage_logging=false)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Config modification did not persist (got: `r(value)')"
}

*==============================================================================
* Test 6: Verify simple format (no installation metadata)
*==============================================================================

di as text "Test 6/6: Verify simple CSV format (no installation metadata)"

* Read the raw file and check it's simple key;value format
local format_ok = 1

tempname fh
file open `fh' using "`config_file'", read
file read `fh' line

* First line should be header: key;value
if (`"`line'"' != "key;value") {
	di as error "  [FAIL] Header is not 'key;value': `line'"
	local format_ok = 0
}
else {
	di as result "  [OK] Header format correct: key;value"
}

* Read remaining lines - should all be key;value pairs, no complex structure
local line_count = 0
file read `fh' line
while (r(eof) == 0) {
	local ++line_count
	* Each line should contain exactly one semicolon
	local sep_pos = strpos(`"`line'"', ";")
	if (`sep_pos' == 0) {
		di as error "  [FAIL] Line has no semicolon delimiter: `line'"
		local format_ok = 0
	}
	file read `fh' line
}
file close `fh'

if (`line_count' > 0 & `format_ok' == 1) {
	di as result "  [PASS] Simple CSV format verified (`line_count' config entries)"
	local ++tests_passed
}
else if (`line_count' == 0) {
	di as error "  [FAIL] Config file has no data rows"
}
else {
	di as error "  [FAIL] Format validation failed"
}

*==============================================================================
* Cleanup
*==============================================================================

cap erase "`config_file'"
cap _rs_utils del_folder_rec "`test_dir'"
global registream_dir ""

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 01 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
