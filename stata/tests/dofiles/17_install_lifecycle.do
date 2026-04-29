/*==============================================================================
  Test 17: Install lifecycle — registream + autolabel + datamirror

  Simulates the install/uninstall/reinstall flow an institutional user
  (e.g. SCB / Statistics Sweden) goes through. Net-installs from the
  per-package folders under registream-website/data/registream/stata/
  <pkg>/<version>/ — the same content registream.org serves.

  Sections:
    1. Canonical install order (rs -> al -> dm) — the happy path
    2. Module-first refusal: autolabel without core errors cleanly
    3. Selective uninstall: remove autolabel; rs + dm keep working
    4. Total uninstall + cleanup
    5. Fresh reinstall after total uninstall
    6. Min-core mismatch: autolabel against too-old core errors clearly

  Each section runs in isolation by pointing PLUS to a fresh temp dir,
  so we never touch the user's real ~/ado/plus/ or STATA.TRK.

  Author: Jeffrey Clark
==============================================================================*/

clear all
version 16.0

* ── Resolve paths ─────────────────────────────────────────────────────────
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
global TEST_LOGS_DIR "$TEST_DIR/logs"
cap mkdir "$TEST_LOGS_DIR"

* The per-package folders live under registream-website (sibling repo)
local website "`project_root'/../registream-website"
local stata_root "`website'/data/registream/stata"

local rs_pkg  "`stata_root'/registream/3.0.0"
local al_pkg  "`stata_root'/autolabel/3.0.0"
local dm_pkg  "`stata_root'/datamirror/1.0.0"

foreach p in `rs_pkg' `al_pkg' `dm_pkg' {
	cap confirm file "`p'/stata.toc"
	if _rc != 0 {
		di as error "ERROR: missing per-package folder: `p'"
		di as error "Run registream/sync_artifacts.sh --build first."
		exit 601
	}
}

di as result ""
di as result "============================================================"
di as result "Test 17: Install lifecycle"
di as result "============================================================"
di as result ""

* Earlier tests in the master runner do `adopath ++ "$SRC_DIR"` to make
* the in-source registream code reachable. That addition lingers into
* this test and would let `which registream` find the source copy even
* after we uninstall from the isolated PLUS dir. Strip those entries
* up front so install/uninstall is observable through `which`.
cap adopath - "$PROJECT_ROOT/stata/src"
cap adopath - "$PROJECT_ROOT/../autolabel/stata/src"
cap adopath - "$PROJECT_ROOT/../datamirror/stata/src"

local total = 6
local passed = 0

* ── Helper: redirect ado/plus to an isolated temp dir ─────────────────────
* Saves the original PLUS so we can restore it at the end. Sets a clean
* dir, restarts adopath via `discard`, and verifies it took.
capture program drop _rs_test_isolate_plus
program define _rs_test_isolate_plus
	args temp_root
	cap mkdir "`temp_root'"
	cap mkdir "`temp_root'/plus"
	sysdir set PLUS "`temp_root'/plus"
	* Refresh adopath cache
	discard
end

* Helper: assert a command exists on the adopath
capture program drop _rs_test_assert_installed
program define _rs_test_assert_installed
	args cmd
	cap which `cmd'
	if _rc != 0 {
		di as error "  ASSERT FAIL: `cmd' should be installed but isn't"
		exit 9
	}
end

capture program drop _rs_test_assert_uninstalled
program define _rs_test_assert_uninstalled
	args cmd
	cap which `cmd'
	if _rc == 0 {
		di as error "  ASSERT FAIL: `cmd' should be uninstalled but is still on adopath"
		exit 9
	}
end

* Save original PLUS so we can restore at the end
local orig_plus "`c(sysdir_plus)'"

*==============================================================================
* Section 1: Canonical install order — rs -> al -> dm
*==============================================================================

di as text "1/6: canonical install (rs -> al -> dm)"

tempfile s1_root
local s1 = "`s1_root'_dir"
_rs_test_isolate_plus "`s1'"

cap noi net install registream, from("`rs_pkg'") replace
local rc1 = _rc
cap noi net install autolabel,  from("`al_pkg'") replace
local rc2 = _rc
cap noi net install datamirror, from("`dm_pkg'") replace
local rc3 = _rc

if (`rc1' == 0 & `rc2' == 0 & `rc3' == 0) {
	_rs_test_assert_installed registream
	_rs_test_assert_installed autolabel
	_rs_test_assert_installed datamirror
	di as result "  [PASS] all three installed cleanly"
	local ++passed
}
else {
	di as error "  [FAIL] install rc: rs=`rc1' al=`rc2' dm=`rc3'"
}

*==============================================================================
* Section 2: Module-first refusal — autolabel without core
*==============================================================================

di as text "2/6: module-without-core errors with clear message (rc=198)"

tempfile s2_root
local s2 = "`s2_root'_dir"
_rs_test_isolate_plus "`s2'"

cap noi net install autolabel, from("`al_pkg'") replace
local rc_install = _rc

* Install succeeded (it ships its own files), but loading should fail
* because registream core is not on adopath.
cap noi autolabel
local rc_run = _rc

if (`rc_install' == 0 & `rc_run' == 198) {
	di as result "  [PASS] autolabel loaded but errored at runtime (rc=198)"
	local ++passed
}
else {
	di as error "  [FAIL] expected install rc=0 + runtime rc=198, got `rc_install' / `rc_run'"
}

*==============================================================================
* Section 3: Selective uninstall — remove autolabel, rs + dm still work
*==============================================================================

di as text "3/6: uninstall autolabel; registream + datamirror still on adopath"

tempfile s3_root
local s3 = "`s3_root'_dir"
_rs_test_isolate_plus "`s3'"

cap noi net install registream, from("`rs_pkg'") replace
cap noi net install autolabel,  from("`al_pkg'") replace
cap noi net install datamirror, from("`dm_pkg'") replace

cap noi ado uninstall autolabel
local rc_un = _rc
discard

cap which registream
local rs_ok = (_rc == 0)
cap which autolabel
local al_gone = (_rc != 0)
cap which datamirror
local dm_ok = (_rc == 0)

if (`rc_un' == 0 & `rs_ok' & `al_gone' & `dm_ok') {
	di as result "  [PASS] autolabel removed; rs + dm intact"
	local ++passed
}
else {
	di as error "  [FAIL] uninstall rc=`rc_un' rs_ok=`rs_ok' al_gone=`al_gone' dm_ok=`dm_ok'"
}

*==============================================================================
* Section 4: Total uninstall (each package one at a time)
*==============================================================================

di as text "4/6: total uninstall removes all three"

tempfile s4_root
local s4 = "`s4_root'_dir"
_rs_test_isolate_plus "`s4'"

cap noi net install registream, from("`rs_pkg'") replace
cap noi net install autolabel,  from("`al_pkg'") replace
cap noi net install datamirror, from("`dm_pkg'") replace

cap noi ado uninstall datamirror
local rc_dm = _rc
cap noi ado uninstall autolabel
local rc_al = _rc
cap noi ado uninstall registream
local rc_rs = _rc
discard

cap which registream
local rs_gone = (_rc != 0)
cap which autolabel
local al_gone = (_rc != 0)
cap which datamirror
local dm_gone = (_rc != 0)

if (`rc_rs' == 0 & `rc_al' == 0 & `rc_dm' == 0 & `rs_gone' & `al_gone' & `dm_gone') {
	di as result "  [PASS] all three uninstalled cleanly"
	local ++passed
}
else {
	di as error "  [FAIL] uninstall rc: rs=`rc_rs' al=`rc_al' dm=`rc_dm'; gone: rs=`rs_gone' al=`al_gone' dm=`dm_gone'"
}

*==============================================================================
* Section 5: Fresh reinstall after total uninstall
*==============================================================================

di as text "5/6: reinstall after total uninstall reaches the same end state"

tempfile s5_root
local s5 = "`s5_root'_dir"
_rs_test_isolate_plus "`s5'"

cap noi net install registream, from("`rs_pkg'") replace
cap noi net install autolabel,  from("`al_pkg'") replace
cap noi net install datamirror, from("`dm_pkg'") replace

cap noi ado uninstall registream
cap noi ado uninstall autolabel
cap noi ado uninstall datamirror
discard

* Now reinstall in canonical order
cap noi net install registream, from("`rs_pkg'") replace
local rc1b = _rc
cap noi net install autolabel,  from("`al_pkg'") replace
local rc2b = _rc
cap noi net install datamirror, from("`dm_pkg'") replace
local rc3b = _rc

if (`rc1b' == 0 & `rc2b' == 0 & `rc3b' == 0) {
	_rs_test_assert_installed registream
	_rs_test_assert_installed autolabel
	_rs_test_assert_installed datamirror
	di as result "  [PASS] reinstall reached clean state"
	local ++passed
}
else {
	di as error "  [FAIL] reinstall rc: rs=`rc1b' al=`rc2b' dm=`rc3b'"
}

*==============================================================================
* Section 6: Min-core mismatch — autolabel refuses too-old core
*==============================================================================

di as text "6/6: autolabel refuses to load against too-old core (rc=198)"

tempfile s6_root
local s6 = "`s6_root'_dir"
_rs_test_isolate_plus "`s6'"

cap noi net install registream, from("`rs_pkg'") replace
cap noi net install autolabel,  from("`al_pkg'") replace

* Spoof core version via dev override (REGISTREAM_TEST_VERSION wins
* inside _rs_get_core_version when stata/dev/version_override.do is
* sourced into the running session).
global REGISTREAM_TEST_VERSION "1.0.0"
do "$PROJECT_ROOT/stata/dev/version_override.do"

* Now autolabel will see core=1.0.0 but its built MIN_CORE is 3.0.0
cap noi autolabel
local rc_too_old = _rc
global REGISTREAM_TEST_VERSION ""

if (`rc_too_old' == 198) {
	di as result "  [PASS] autolabel refused too-old core with rc=198"
	local ++passed
}
else {
	di as error "  [FAIL] expected rc=198, got `rc_too_old'"
}

*==============================================================================
* Cleanup
*==============================================================================

sysdir set PLUS "`orig_plus'"
discard

di as result ""
di as result "============================================================"
if (`passed' == `total') {
	di as result "Test 17 PASSED: `passed'/`total' sections passed"
}
else {
	di as error "Test 17 FAILED: `passed'/`total' sections passed"
	exit 9
}
di as result "============================================================"
