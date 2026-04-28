* =============================================================================
* RegiStream Update Checker
* Handles package update detection via heartbeat and notification display.
* All update checks go through the /api/v1/heartbeat endpoint which
* returns per-module version info (registream, autolabel, datamirror).
*
* State passes via rclass return values and the config file — no globals.
* Callers:
*   - send_heartbeat returns r(update_available), r(latest_version),
*     r(autolabel_update), r(autolabel_latest), r(datamirror_update),
*     r(datamirror_latest), r(reason).
*   - show_notification takes the above as options plus scope().
* Usage: _rs_updates subcommand [args]
* =============================================================================

program define _rs_updates, rclass
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "check_package") {
		_upd_check_package `0'
		return add
	}
	else if ("`subcmd'" == "show_notification") {
		_upd_show_notification `0'
	}
	else if ("`subcmd'" == "send_heartbeat") {
		_upd_send_heartbeat `0'
		return add
	}
	else {
		di as error "Invalid _rs_updates subcommand: `subcmd'"
		exit 198
	}
end

* -----------------------------------------------------------------------------
* check_package: Interactive update check for `registream update` command
* Delegates to send_heartbeat (the single source of truth). Forces a fresh
* check by expiring the 24h cache.
*
* Positional args (all quoted):
*   1. registream_dir
*   2. current_version (core version)
*   3. command_string
*   4. module           — calling module ("" for core/meta)
*   5. module_version   — calling module's version ("" for core/meta)
*   6. autolabel_ver    — pre-detected autolabel version for TRK sweep
*   7. datamirror_ver   — pre-detected datamirror version for TRK sweep
*
* Returns: r(update_available), r(current_version), r(latest_version),
*          r(autolabel_update), r(autolabel_latest),
*          r(datamirror_update), r(datamirror_latest), r(reason)
* -----------------------------------------------------------------------------
program define _upd_check_package, rclass
	gettoken registream_dir 0 : 0
	gettoken current_version 0 : 0
	gettoken command_string 0 : 0, qed(q)
	gettoken module 0 : 0
	gettoken module_version 0 : 0
	gettoken al_ver 0 : 0
	gettoken dm_ver 0 : 0

	if ("`current_version'" == "") {
		di as error "_rs_updates: version not provided"
		exit 198
	}

	* Check internet access first (fast exit)
	_rs_config get "`registream_dir'" "internet_access"
	if (r(found) == 1 & "`r(value)'" == "false") {
		return scalar update_available = 0
		return local current_version "`current_version'"
		return local latest_version ""
		return scalar autolabel_update = 0
		return local autolabel_latest ""
		return scalar datamirror_update = 0
		return local datamirror_latest ""
		return local reason "internet_disabled"
		exit 0
	}

	* Expire cache to force immediate check (user explicitly asked)
	local now = clock("`c(current_date)' `c(current_time)'", "DMY hms")
	local old = `now' - 90000000
	_rs_config set "`registream_dir'" "last_update_check" "`old'"

	* Delegate to heartbeat (positional: dir ver cmd module mv al dm)
	cap noi _rs_updates send_heartbeat "`registream_dir'" "`current_version'" ///
		`"`command_string'"' "`module'" "`module_version'" "`al_ver'" "`dm_ver'"

	if (_rc != 0) {
		return scalar update_available = 0
		return local current_version "`current_version'"
		return local latest_version ""
		return scalar autolabel_update = 0
		return local autolabel_latest ""
		return scalar datamirror_update = 0
		return local datamirror_latest ""
		return local reason "network_error"
		exit 0
	}

	return scalar update_available = r(update_available)
	return local latest_version "`r(latest_version)'"
	return local current_version "`current_version'"
	return scalar autolabel_update = r(autolabel_update)
	return local autolabel_latest "`r(autolabel_latest)'"
	return scalar datamirror_update = r(datamirror_update)
	return local datamirror_latest "`r(datamirror_latest)'"
	return local reason "`r(reason)'"
end

* -----------------------------------------------------------------------------
* show_notification: Display update banner(s) for whichever flags are set.
* Takes flags as options — no globals.
*
* Scope policy (2026-04-17 decision): core always; siblings suppressed.
*   scope="" or "core" : notify about registream + autolabel + datamirror
*                        (explicit `registream update` meta-command)
*   scope="autolabel"  : notify about registream + autolabel only
*   scope="datamirror" : notify about registream + datamirror only
*
* Options:
*   current_version(str)      caller's core version (shown in banner)
*   scope(str)                core|autolabel|datamirror (default: core)
*   core_update(0/1)          core update flag
*   core_latest(str)          core latest version
*   autolabel_update(0/1)     autolabel update flag
*   autolabel_latest(str)     autolabel latest version
*   datamirror_update(0/1)    datamirror update flag
*   datamirror_latest(str)    datamirror latest version
* -----------------------------------------------------------------------------
program define _upd_show_notification
	syntax , Current_version(string) ///
		[SCope(string) ///
		Core_update(integer 0) Core_latest(string) ///
		Autolabel_update(integer 0) Autolabel_latest(string) ///
		Datamirror_update(integer 0) Datamirror_latest(string)]

	* Default scope is "core" (= show all modules) when unspecified.
	if ("`scope'" == "") local scope "core"

	* Core banner: always shown when an update is available (and cached
	* latest differs from current, guarding against stale cache).
	if (`core_update' == 1 & "`current_version'" != "`core_latest'") {
		di as text ""
		di as result "{hline 60}"
		di as result "A new version of registream is available!"
		di as text "  Current version:  `current_version'"
		di as text "  Latest version:   `core_latest'"
		di as text ""
		di as text "To update, run: {stata registream update:registream update}"
		di as result "{hline 60}"
		di as text ""
	}

	* Autolabel banner: shown in core scope or when autolabel is the caller.
	if ("`scope'" == "core" | "`scope'" == "autolabel") {
		if (`autolabel_update' == 1 & "`autolabel_latest'" != "") {
			di as text ""
			di as result "{hline 60}"
			di as result "A new version of autolabel is available!"
			di as text "  Latest version:   `autolabel_latest'"
			di as text ""
			di as text "To update:"
			di as text `"  cap ado uninstall autolabel"'
			di as text `"  net install autolabel, from("https://registream.org/install/stata/latest") replace"'
			di as result "{hline 60}"
			di as text ""
		}
	}

	* Datamirror banner: shown in core scope or when datamirror is the caller.
	if ("`scope'" == "core" | "`scope'" == "datamirror") {
		if (`datamirror_update' == 1 & "`datamirror_latest'" != "") {
			di as text ""
			di as result "{hline 60}"
			di as result "A new version of datamirror is available!"
			di as text "  Latest version:   `datamirror_latest'"
			di as text ""
			di as text "To update:"
			di as text `"  cap ado uninstall datamirror"'
			di as text `"  net install datamirror, from("https://registream.org/install/stata/latest") replace"'
			di as result "{hline 60}"
			di as text ""
		}
	}
end

* -----------------------------------------------------------------------------
* send_heartbeat: Consolidated telemetry + update check via heartbeat API
* TELEMETRY: batched usage rows newer than last_update_check (parity with
*   Python _read_usage_since / R read_pending_usage). No session global.
* UPDATES: Checked once per 24 hours; cache-hit rehydrates per-module
*   update state from config into r() return values.
*
* Positional args (all quoted):
*   1. registream_dir
*   2. current_version (core version)
*   3. command_string
*   4. module           — caller's module name ("" for core/meta)
*   5. module_version   — caller's module version
*   6. autolabel_ver    — pre-detected autolabel version (TRK sweep)
*   7. datamirror_ver   — pre-detected datamirror version (TRK sweep)
*
* Returns (rclass):
*   r(update_available)   core update flag (0/1)
*   r(latest_version)     core latest version string
*   r(autolabel_update)   autolabel update flag (0/1)
*   r(autolabel_latest)   autolabel latest version string
*   r(datamirror_update)  datamirror update flag (0/1)
*   r(datamirror_latest)  datamirror latest version string
*   r(reason)             "success" | "cached" | "internet_disabled" |
*                         "network_error"
* -----------------------------------------------------------------------------
program define _upd_send_heartbeat, rclass
	gettoken registream_dir 0 : 0
	gettoken current_version 0 : 0
	gettoken command_string 0 : 0, qed(q)
	gettoken module 0 : 0
	gettoken module_version 0 : 0
	gettoken al_ver 0 : 0
	gettoken dm_ver 0 : 0

	* Resolve per-module versions: if caller passed explicit al_ver/dm_ver,
	* use those; else infer from module()/module_version() when the caller
	* IS that module.
	if ("`al_ver'" == "" & "`module'" == "autolabel") local al_ver "`module_version'"
	if ("`dm_ver'" == "" & "`module'" == "datamirror") local dm_ver "`module_version'"

	* Default return: everything zero/empty; overwritten below.
	return scalar update_available = 0
	return local latest_version ""
	return scalar autolabel_update = 0
	return local autolabel_latest ""
	return scalar datamirror_update = 0
	return local datamirror_latest ""
	return local reason "success"

	* Check internet access; skip everything if offline
	_rs_config get "`registream_dir'" "internet_access"
	local internet_access "`r(value)'"
	if ("`internet_access'" == "") local internet_access "true"

	if ("`internet_access'" == "false") {
		return local reason "internet_disabled"
		exit 0
	}

	_rs_config get "`registream_dir'" "telemetry_enabled"
	local telemetry_enabled "`r(value)'"

	_rs_config get "`registream_dir'" "auto_update_check"
	local update_enabled "`r(value)'"
	if ("`update_enabled'" == "") local update_enabled "true"

	local send_telemetry = 0
	if ("`telemetry_enabled'" == "true" | "`telemetry_enabled'" == "1") {
		local send_telemetry = 1
	}

	local current_clock = clock("`c(current_date)' `c(current_time)'", "DMY hms")

	local check_updates = 0
	if ("`update_enabled'" == "true" | "`update_enabled'" == "1") {
		_rs_config get "`registream_dir'" "last_update_check"
		local last_check "`r(value)'"

		if ("`last_check'" == "" | "`last_check'" == ".") {
			local check_updates = 1
		}
		else {
			local time_diff_ms = `current_clock' - `last_check'
			if (`time_diff_ms' >= 86400000) {
				local check_updates = 1
			}
		}
	}

	* Cache-hit: rehydrate ALL fields (core + modules) from config and
	* return. No network call.
	if (`check_updates' == 0) {
		_rs_config get "`registream_dir'" "update_available"
		if (r(found) == 1 & "`r(value)'" == "true") {
			return scalar update_available = 1
			_rs_config get "`registream_dir'" "latest_version"
			return local latest_version "`r(value)'"
		}

		_rs_config get "`registream_dir'" "autolabel_update_available"
		if (r(found) == 1 & "`r(value)'" == "true") {
			return scalar autolabel_update = 1
			_rs_config get "`registream_dir'" "autolabel_latest_version"
			return local autolabel_latest "`r(value)'"
		}

		_rs_config get "`registream_dir'" "datamirror_update_available"
		if (r(found) == 1 & "`r(value)'" == "true") {
			return scalar datamirror_update = 1
			_rs_config get "`registream_dir'" "datamirror_latest_version"
			return local datamirror_latest "`r(value)'"
		}

		return local reason "cached"
		exit 0
	}

	* Get API host
	_rs_utils get_api_host
	local api_host "`r(host)'"

	local timestamp "`c(current_date)'T`c(current_time)'Z"

	* Build heartbeat URL
	if (`send_telemetry' == 1) {
		_rs_usage compute_user_id "`registream_dir'"
		local user_id "`r(user_id)'"

		local platform "stata"
		local os "`c(os)'"
		if ("`os'" == "Unix") {
			if ("`c(machine_type)'" == "Macintosh (Intel 64-bit)" | "`c(machine_type)'" == "Macintosh (ARM 64-bit)") {
				local os "MacOSX"
			}
			else {
				local os "Linux"
			}
		}
		local platform_version "`c(stata_version)'"

		local timestamp_encoded : subinstr local timestamp " " "%20", all

		* Read batched usage rows since last_update_check from usage_stata.csv
		* (matches Python/R batching pattern; no session global).
		_upd_read_pending_usage "`registream_dir'" "`last_check'"
		local command_to_send `"`r(batch)'"'
		if ("`command_to_send'" == "") {
			local command_to_send `"`command_string'"'
		}

		* URL-encode
		local command_encoded : subinstr local command_to_send " " "%20", all
		local command_encoded : subinstr local command_encoded "," "%2C", all
		local command_encoded : subinstr local command_encoded "(" "%28", all
		local command_encoded : subinstr local command_encoded ")" "%29", all
		local command_encoded : subinstr local command_encoded "|" "%7C", all

		if (strlen("`command_encoded'") > 1500) {
			local command_encoded = substr("`command_encoded'", 1, 1500)
		}

		local heartbeat_url "`api_host'/api/v1/heartbeat?user_id=`user_id'&command=`command_encoded'&platform=`platform'&os=`os'&platform_version=`platform_version'&timestamp=`timestamp_encoded'&registream=`current_version'&format=stata"
	}
	else {
		local heartbeat_url "`api_host'/api/v1/heartbeat?registream=`current_version'&format=stata"
	}

	if ("`al_ver'" != "") {
		local heartbeat_url "`heartbeat_url'&autolabel=`al_ver'"
	}
	if ("`dm_ver'" != "") {
		local heartbeat_url "`heartbeat_url'&datamirror=`dm_ver'"
	}

	tempfile response
	cap copy "`heartbeat_url'" "`response'", replace

	if (_rc != 0) {
		return local reason "network_error"
		exit 0
	}

	local rs_update ""
	local rs_latest ""
	local al_update ""
	local al_latest ""
	local dm_update ""
	local dm_latest ""

	tempname fh
	cap file open `fh' using "`response'", read text
	if (_rc != 0) {
		return local reason "network_error"
		exit 0
	}
	file read `fh' line
	while (r(eof) == 0) {
		if (regexm("`line'", "^registream_update=(.+)$")) {
			local rs_update = cond(trim(regexs(1)) == "true", "1", "0")
		}
		else if (regexm("`line'", "^registream_latest=(.+)$")) {
			local rs_latest = trim(regexs(1))
		}
		else if (regexm("`line'", "^autolabel_update=(.+)$")) {
			local al_update = cond(trim(regexs(1)) == "true", "1", "0")
		}
		else if (regexm("`line'", "^autolabel_latest=(.+)$")) {
			local al_latest = trim(regexs(1))
		}
		else if (regexm("`line'", "^datamirror_update=(.+)$")) {
			local dm_update = cond(trim(regexs(1)) == "true", "1", "0")
		}
		else if (regexm("`line'", "^datamirror_latest=(.+)$")) {
			local dm_latest = trim(regexs(1))
		}
		file read `fh' line
	}
	file close `fh'

	* Core update flag
	if ("`rs_update'" == "1") {
		return scalar update_available = 1
		return local latest_version "`rs_latest'"
		cap _rs_config set "`registream_dir'" "update_available" "true"
		cap _rs_config set "`registream_dir'" "latest_version" "`rs_latest'"
	}
	else {
		cap _rs_config set "`registream_dir'" "update_available" "false"
		cap _rs_config set "`registream_dir'" "latest_version" ""
	}

	* Autolabel: only overwrite cache when we asked the server about
	* autolabel (i.e., al_ver was sent). Preserves prior cached state
	* for untouched modules.
	if ("`al_ver'" != "") {
		if ("`al_update'" == "1") {
			return scalar autolabel_update = 1
			return local autolabel_latest "`al_latest'"
			cap _rs_config set "`registream_dir'" "autolabel_update_available" "true"
			cap _rs_config set "`registream_dir'" "autolabel_latest_version" "`al_latest'"
		}
		else {
			cap _rs_config set "`registream_dir'" "autolabel_update_available" "false"
			cap _rs_config set "`registream_dir'" "autolabel_latest_version" ""
		}
	}

	* Datamirror: same policy.
	if ("`dm_ver'" != "") {
		if ("`dm_update'" == "1") {
			return scalar datamirror_update = 1
			return local datamirror_latest "`dm_latest'"
			cap _rs_config set "`registream_dir'" "datamirror_update_available" "true"
			cap _rs_config set "`registream_dir'" "datamirror_latest_version" "`dm_latest'"
		}
		else {
			cap _rs_config set "`registream_dir'" "datamirror_update_available" "false"
			cap _rs_config set "`registream_dir'" "datamirror_latest_version" ""
		}
	}

	cap _rs_config set "`registream_dir'" "last_update_check" "`current_clock'"
end

* -----------------------------------------------------------------------------
* _upd_read_pending_usage: Read usage_stata.csv rows newer than since_clock,
* return a pipe-delimited "module command_string" batch in r(batch).
* Matches Python's _read_usage_since / R's read_pending_usage. No session
* global needed.
* -----------------------------------------------------------------------------
program define _upd_read_pending_usage, rclass
	args registream_dir since_clock

	return local batch ""

	local usage_file "`registream_dir'/usage_stata.csv"
	if (!fileexists("`usage_file'")) exit 0

	tempname fh
	cap file open `fh' using "`usage_file'", read text
	if (_rc != 0) exit 0

	local batch ""
	local count 0

	* Skip header
	file read `fh' line

	file read `fh' line
	while (r(eof) == 0) {
		* Columns: timestamp;user_id;platform;module;module_version;core_version;command_string;os;platform_version
		* tokenize on ";" — real values land at odd token positions.
		tokenize `"`line'"', parse(";")
		local ts `"`1'"'
		local mod `"`7'"'
		local cmd `"`13'"'

		* Include only rows newer than since_clock (compare as clock ms).
		local include 1
		if ("`since_clock'" != "" & "`since_clock'" != ".") {
			local row_clock = clock("`ts'", "YMDhms")
			if ("`row_clock'" != "." & `row_clock' <= `since_clock') {
				local include 0
			}
		}

		if (`include' == 1 & `"`cmd'"' != "") {
			local piece `"`mod' `cmd'"'
			if ("`batch'" == "") {
				local batch `"`piece'"'
			}
			else {
				local batch `"`batch'|`piece'"'
			}
			local ++count
			if (`count' >= 50) {
				* Safety cap on batch size
				continue, break
			}
		}

		file read `fh' line
	}
	file close `fh'

	return local batch `"`batch'"'
end
