/*==============================================================================
  Test 11: Telemetry Config
  Tests all 12 aspects of telemetry and config system behavior
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
* Setup: Isolated temp directory for config isolation
*==============================================================================

tempfile tmpbase
local test_dir = "`tmpbase'_telemetry"
cap mkdir "`test_dir'"
global registream_dir "`test_dir'"

di as result ""
di as result "============================================================"
di as result "Test 11: Telemetry Config"
di as result "============================================================"
di as result ""

local tests_passed = 0
local tests_total = 12

*==============================================================================
* Test 1: Fresh config creates all expected fields
*==============================================================================

di as text "Test 1/12: Fresh config creates all expected fields"

_rs_config init "`test_dir'"

local all_found = 1
foreach key in usage_logging telemetry_enabled internet_access auto_update_check last_update_check update_available latest_version {
	_rs_config get "`test_dir'" "`key'"
	if (r(found) == 0) {
		di as error "  [FAIL] Missing field: `key'"
		local all_found = 0
	}
}

if (`all_found' == 1) {
	di as result "  [PASS] All expected fields present in config"
	local ++tests_passed
}

*==============================================================================
* Test 2: Default telemetry_enabled is true (Full Mode in auto-approve)
*==============================================================================

di as text "Test 2/12: Default telemetry_enabled = true (auto-approve = Full Mode)"

_rs_config get "`test_dir'" "telemetry_enabled"
if ("`r(value)'" == "true") {
	di as result "  [PASS] telemetry_enabled defaults to true"
	local ++tests_passed
}
else {
	di as error "  [FAIL] telemetry_enabled = `r(value)' (expected true)"
}

*==============================================================================
* Test 3: Set telemetry_enabled to false
*==============================================================================

di as text "Test 3/12: Set telemetry_enabled to false"

_rs_config set "`test_dir'" "telemetry_enabled" "false"
_rs_config get "`test_dir'" "telemetry_enabled"
if ("`r(value)'" == "false") {
	di as result "  [PASS] telemetry_enabled set to false"
	local ++tests_passed
}
else {
	di as error "  [FAIL] telemetry_enabled = `r(value)' (expected false)"
}

*==============================================================================
* Test 4: Set telemetry_enabled back to true
*==============================================================================

di as text "Test 4/12: Set telemetry_enabled back to true"

_rs_config set "`test_dir'" "telemetry_enabled" "true"
_rs_config get "`test_dir'" "telemetry_enabled"
if ("`r(value)'" == "true") {
	di as result "  [PASS] telemetry_enabled restored to true"
	local ++tests_passed
}
else {
	di as error "  [FAIL] telemetry_enabled = `r(value)' (expected true)"
}

*==============================================================================
* Test 5: usage_logging independent of telemetry
*==============================================================================

di as text "Test 5/12: usage_logging is independent of telemetry"

_rs_config set "`test_dir'" "telemetry_enabled" "false"
_rs_config set "`test_dir'" "usage_logging" "true"

_rs_config get "`test_dir'" "telemetry_enabled"
local tel "`r(value)'"
_rs_config get "`test_dir'" "usage_logging"
local usg "`r(value)'"

if ("`tel'" == "false" & "`usg'" == "true") {
	di as result "  [PASS] usage_logging=true while telemetry_enabled=false"
	local ++tests_passed
}
else {
	di as error "  [FAIL] telemetry=`tel', usage=`usg'"
}

*==============================================================================
* Test 6: internet_access controls update checks
*==============================================================================

di as text "Test 6/12: internet_access=false disables update checks"

_rs_config set "`test_dir'" "internet_access" "false"

_rs_utils get_version
local ver "`r(version)'"
cap noi _rs_updates check_package "`test_dir'" "`ver'"
local reason "`r(reason)'"

if ("`reason'" == "internet_disabled") {
	di as result "  [PASS] internet_access=false returns internet_disabled"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected internet_disabled, got: `reason'"
}

_rs_config set "`test_dir'" "internet_access" "true"

*==============================================================================
* Test 7: registream config command validates input
*==============================================================================

di as text "Test 7/12: Config command validates boolean inputs"

cap noi registream config, telemetry_enabled(invalid)
local rc7 = _rc

if (`rc7' == 198) {
	di as result "  [PASS] Config rejects invalid boolean value (rc=198)"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected rc=198 for invalid input, got rc=`rc7'"
}

*==============================================================================
* Test 8: Multiple config sets don't corrupt file
*==============================================================================

di as text "Test 8/12: Rapid sequential config sets don't corrupt"

_rs_config set "`test_dir'" "usage_logging" "false"
_rs_config set "`test_dir'" "telemetry_enabled" "true"
_rs_config set "`test_dir'" "internet_access" "false"
_rs_config set "`test_dir'" "auto_update_check" "false"

* Read all back
_rs_config get "`test_dir'" "usage_logging"
local v1 "`r(value)'"
_rs_config get "`test_dir'" "telemetry_enabled"
local v2 "`r(value)'"
_rs_config get "`test_dir'" "internet_access"
local v3 "`r(value)'"
_rs_config get "`test_dir'" "auto_update_check"
local v4 "`r(value)'"

if ("`v1'" == "false" & "`v2'" == "true" & "`v3'" == "false" & "`v4'" == "false") {
	di as result "  [PASS] All 4 sequential sets persisted correctly"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Values: usage=`v1', telemetry=`v2', internet=`v3', auto_update=`v4'"
}

*==============================================================================
* Test 9: Config path helper
*==============================================================================

di as text "Test 9/12: Config path helper returns correct path"

_rs_config path "`test_dir'"
local config_path "`r(config_file)'"

if ("`config_path'" == "`test_dir'/config_stata.csv") {
	di as result "  [PASS] Config path: `config_path'"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Expected `test_dir'/config_stata.csv, got: `config_path'"
}

*==============================================================================
* Test 10: Config get on missing key returns empty
*==============================================================================

di as text "Test 10/12: Get missing key returns empty with found=0"

_rs_config get "`test_dir'" "nonexistent_key_xyz"
if (r(found) == 0 & "`r(value)'" == "") {
	di as result "  [PASS] Missing key returns found=0, value=''"
	local ++tests_passed
}
else {
	di as error "  [FAIL] found=`r(found)', value=`r(value)'"
}

*==============================================================================
* Test 11: Config get on missing file returns gracefully
*==============================================================================

di as text "Test 11/12: Get from nonexistent config file returns gracefully"

tempfile tmpbase2
local empty_dir = "`tmpbase2'_empty"
cap mkdir "`empty_dir'"

_rs_config get "`empty_dir'" "usage_logging"
if (r(found) == 0) {
	di as result "  [PASS] Get from missing config returns found=0"
	local ++tests_passed
}
else {
	di as error "  [FAIL] Unexpected found=`r(found)' from empty directory"
}

cap rmdir "`empty_dir'"

*==============================================================================
* Test 12: Config set on missing file triggers auto-init
*==============================================================================

di as text "Test 12/12: Set on missing config triggers auto-initialization"

tempfile tmpbase3
local new_dir = "`tmpbase3'_new"
cap mkdir "`new_dir'"

* Set should trigger init if config doesn't exist
_rs_config set "`new_dir'" "usage_logging" "false"

* Verify the config was created and the value was set
_rs_config get "`new_dir'" "usage_logging"
if (r(found) == 1 & "`r(value)'" == "false") {
	di as result "  [PASS] Set triggered auto-init and persisted value"
	local ++tests_passed
}
else {
	* Check if config file exists at all
	cap confirm file "`new_dir'/config_stata.csv"
	if (_rc != 0) {
		di as error "  [FAIL] Config file was not auto-created"
	}
	else {
		di as error "  [FAIL] Config created but value not set: found=`r(found)', value=`r(value)'"
	}
}

cap erase "`new_dir'/config_stata.csv"
cap rmdir "`new_dir'"

*==============================================================================
* Cleanup
*==============================================================================

* Restore all settings
_rs_config set "`test_dir'" "usage_logging" "true"
_rs_config set "`test_dir'" "telemetry_enabled" "true"
_rs_config set "`test_dir'" "internet_access" "true"
_rs_config set "`test_dir'" "auto_update_check" "true"

cap erase "`test_dir'/config_stata.csv"
cap _rs_utils del_folder_rec "`test_dir'"
global registream_dir ""

*==============================================================================
* Summary
*==============================================================================

di as result ""
di as result "============================================================"
di as result "Test 11 Summary: `tests_passed'/`tests_total' tests passed"
di as result "============================================================"
di as result ""

if (`tests_passed' < `tests_total') {
	exit 1
}
