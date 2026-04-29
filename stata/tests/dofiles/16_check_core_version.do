/*==============================================================================
  Test 16: _rs_utils check_core_version — runtime min-core check used by modules
  to refuse to load against an incompatible core. See
  registream-docs/architecture/version_coordination.md (Phase 3).

  Covers:
    1. Pass when core_version == required
    2. Pass when core_version > required
    3. Fail (exit 198) when core_version < required
    4. Module name appears in error message
    5. Empty/missing args rejected

  Author: Jeffrey Clark
==============================================================================*/

clear all
version 16.0

* Find project root (same boilerplate as other tests)
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
* Load version_override.do so we can set $REGISTREAM_TEST_VERSION to
* spoof the installed core version without writing tempfiles.
do "$SRC_DIR/../dev/version_override.do"
do "$SRC_DIR/../dev/auto_approve.do"

di as result ""
di as result "============================================================"
di as result "Test 16: _rs_utils check_core_version"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 5

*==============================================================================
* Test 1: Pass when core == required
*==============================================================================

di as text "Test 1/5: pass when core_version == required"

global REGISTREAM_TEST_VERSION "3.0.1"
do "$SRC_DIR/../dev/version_override.do"

cap _rs_utils check_core_version "autolabel" "3.0.1"
if (_rc == 0) {
	di as result "  [PASS] check passed (rc=0)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] expected rc=0, got rc=`_rc'"
}

*==============================================================================
* Test 2: Pass when core > required
*==============================================================================

di as text "Test 2/5: pass when core_version > required"

global REGISTREAM_TEST_VERSION "3.0.5"
do "$SRC_DIR/../dev/version_override.do"

cap _rs_utils check_core_version "datamirror" "3.0.1"
if (_rc == 0) {
	di as result "  [PASS] check passed (rc=0)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] expected rc=0, got rc=`_rc'"
}

*==============================================================================
* Test 3: Fail with exit 198 when core < required
*==============================================================================

di as text "Test 3/5: fail with rc=198 when core_version < required"

global REGISTREAM_TEST_VERSION "3.0.0"
do "$SRC_DIR/../dev/version_override.do"

cap _rs_utils check_core_version "autolabel" "3.0.1"
if (_rc == 198) {
	di as result "  [PASS] check failed with rc=198"
	local ++tests_passed
}
else {
	di as error "  [FAIL] expected rc=198, got rc=`_rc'"
}

*==============================================================================
* Test 4: Error message contains the module name
*==============================================================================

di as text "Test 4/5: error message names the calling module"

global REGISTREAM_TEST_VERSION "3.0.0"
do "$SRC_DIR/../dev/version_override.do"

* Capture the error output by redirecting to a log
tempfile errlog
cap log close _all
log using "`errlog'", text replace
cap noisily _rs_utils check_core_version "datamirror" "3.0.1"
log close

local logfile "`errlog'.log"
if (!fileexists("`logfile'")) {
	* Some Stata versions don't add the .log suffix
	local logfile "`errlog'"
}

local found_module 0
tempname fh
cap file open `fh' using "`logfile'", read text
if (_rc == 0) {
	file read `fh' line
	while (r(eof) == 0) {
		if (strpos(`"`line'"', "datamirror") > 0) {
			local found_module 1
		}
		file read `fh' line
	}
	file close `fh'
}

if (`found_module' == 1) {
	di as result "  [PASS] error message mentions 'datamirror'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] error message did not mention 'datamirror'"
}

*==============================================================================
* Test 5: Reject empty arguments
*==============================================================================

di as text "Test 5/5: reject empty (module_name, min_version)"

cap _rs_utils check_core_version "" "3.0.1"
local rc1 = _rc
cap _rs_utils check_core_version "autolabel" ""
local rc2 = _rc

if (`rc1' == 198 & `rc2' == 198) {
	di as result "  [PASS] both empty-arg cases rejected with rc=198"
	local ++tests_passed
}
else {
	di as error "  [FAIL] expected rc=198 for both, got rc1=`rc1', rc2=`rc2'"
}

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
if (`tests_passed' == `tests_total') {
	di as result "Test 16 PASSED: `tests_passed'/`tests_total' tests passed"
}
else {
	di as error "Test 16 FAILED: `tests_passed'/`tests_total' tests passed"
	exit 9
}
di as result "============================================================"
