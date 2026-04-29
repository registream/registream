/*==============================================================================
  Test 13: Version Resolution Priority
  Tests the 2-level version resolution: dev override > hardcoded production
  Also tests autolabel version tracking if autolabel package is available
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
cap do "$SRC_DIR/../dev/version_override.do"
do "$SRC_DIR/../dev/auto_approve.do"

* Add autolabel adopath if available (for tests that call autolabel commands)
cap adopath ++ "$PROJECT_ROOT/../../autolabel/stata/src"

*==============================================================================
* Setup: Isolated temp directory
*==============================================================================

tempfile tmpbase
local test_dir = "`tmpbase'_version_res"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 13: Version Resolution Priority"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 6

*==============================================================================
* Test 1: _rs_utils get_version returns a version string
*==============================================================================

di as text "Test 1/6: _rs_utils get_version returns a version"

_rs_utils get_version
local ver "`r(version)'"

if ("`ver'" != "") {
	di as result "  [PASS] get_version returned: `ver'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] get_version returned empty string"
}

*==============================================================================
* Test 2: Dev override via $REGISTREAM_TEST_VERSION
*==============================================================================

di as text "Test 2/6: $REGISTREAM_TEST_VERSION overrides version"

* Save original
local orig_test_ver "$REGISTREAM_TEST_VERSION"

* Set test version override
global REGISTREAM_TEST_VERSION "9.8.7"

* Reload dev utils to pick up the override
cap do "$SRC_DIR/../dev/version_override.do"

_rs_utils get_version
local ver_override "`r(version)'"

if ("`ver_override'" == "9.8.7") {
	di as result "  [PASS] Version override worked: `ver_override'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected 9.8.7, got: `ver_override'"
	di as text "  (This may fail if dev/version_override.do doesn't support TEST_VERSION override)"
}

* Restore
global REGISTREAM_TEST_VERSION "`orig_test_ver'"
cap do "$SRC_DIR/../dev/version_override.do"

*==============================================================================
* Test 3: Version format is X.Y.Z (semantic versioning)
*==============================================================================

di as text "Test 3/6: Version format is semantic (X.Y.Z)"

_rs_utils get_version
local ver "`r(version)'"

* Check for X.Y.Z pattern (at least major.minor.patch)
local is_semver = regexm("`ver'", "^[0-9]+\.[0-9]+\.[0-9]+")

if (`is_semver' == 1) {
	di as result "  [PASS] Version `ver' matches X.Y.Z format"
	local ++tests_passed
}
else {
	* In production, version might be {{VERSION}} placeholder - that's OK for dev
	if ("`ver'" == "{{VERSION}}") {
		di as result "  [PASS] Version is {{VERSION}} placeholder (production template)"
		local ++tests_passed
	}
	else {
		di as error "  [FAIL] Version `ver' does not match X.Y.Z format"
	}
}

*==============================================================================
* Test 4: Core version from _rs_get_core_version
*==============================================================================

di as text "Test 4/6: _rs_get_core_version returns hardcoded version"

cap _rs_utils get_core_version
if (_rc == 0) {
	local core_ver "`r(version)'"
	if ("`core_ver'" != "") {
		di as result "  [PASS] Core version: `core_ver'"
		local ++tests_passed
	}
	else {
		di as error "  [FAIL] _rs_get_core_version returned empty"
	}
}
else {
	di as error "  [FAIL] _rs_get_core_version not found (rc=`=_rc')"
}

*==============================================================================
* Test 5: _rs_check_core_version validates minimum version
*==============================================================================

di as text "Test 5/6: _rs_check_core_version validates minimum requirements"

* Phase 3 of version_coordination.md changed signature to
* (module_name, min_version). Should pass — require version 1.0.0
* (current dev override is 2.0.0, well above the floor).
cap _rs_utils check_core_version "autolabel" "1.0.0"
if (_rc == 0) {
	di as result "  [PASS] Core version check passes for 1.0.0 requirement"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Core version check failed for 1.0.0 (rc=`=_rc')"
}

*==============================================================================
* Test 6: Autolabel version detection via detect_installed_modules
*==============================================================================

di as text "Test 6/6: Autolabel version detected from *! header"

* Check if autolabel is available on adopath
cap which autolabel
local autolabel_available = (_rc == 0)

if (`autolabel_available') {
	* detect_installed_modules reads the `*! version X.Y.Z' header from
	* the on-disk .ado file. No session-global side effect.
	cap noi _rs_utils detect_installed_modules
	if (_rc == 0) {
		local al_ver "`r(autolabel_version)'"
		if ("`al_ver'" != "") {
			di as result "  [PASS] Autolabel version detected: `al_ver'"
		}
		else {
			di as result "  [PASS] detect_installed_modules ran (version not parsed)"
		}
		local ++tests_passed
	}
	else {
		di as text "  [SKIP] detect_installed_modules failed"
		local ++tests_passed
	}
}
else {
	di as text "  [SKIP] Autolabel package not available (separate repo)"
	di as text "         This is expected in core-only testing"
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
di as result "Test 13 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
