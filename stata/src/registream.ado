*! version {{VERSION}} {{DATE}}
* RegiStream: Main command entry point
* Author: Jeffrey Clark
*
* Syntax:
*   registream update [package|dataset|datasets] [, domain() lang()]  (default: package)
*   registream info
*   registream config
*   registream version
*   registream cite

program define registream, rclass
	version 16.0

	* Get version from helper function (can be overridden by stata/dev/version_override.do)
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	* ==========================================================================
	* MASTER WRAPPER (START): Usage tracking + Background update check
	* Runs for ALL registream commands
	* ==========================================================================
	_registream_wrapper_start "`REGISTREAM_VERSION'" `"`0'"'
	local registream_dir "`r(registream_dir)'"

	* Parse first argument (subcommand)
	gettoken subcmd rest : 0, parse(" ,")

	if ("`subcmd'" == "update") {
		_registream_update `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "info") {
		_registream_info `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "config") {
		_registream_config `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "version") {
		_registream_version `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "cite") {
		_registream_cite `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "stats") {
		_registream_stats `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "uninstall") {
		_registream_uninstall `rest'
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return local version "`REGISTREAM_VERSION'"
		return local dir "`registream_dir'"
		return scalar status = 0
		exit 0
	}
	else if ("`subcmd'" == "") {
		di as error "RegiStream: Please specify a subcommand"
		di as text ""
		di as text "Available subcommands:"
		di as text "  {cmd:registream update} [package|dataset|datasets] - Check for updates (default: package)"
		di as text "  {cmd:registream info}                              - Show configuration"
		di as text "  {cmd:registream config}                            - View/edit config"
		di as text "  {cmd:registream version}                           - Show package version"
		di as text "  {cmd:registream cite}                              - Show citation"
		di as text "  {cmd:registream stats} [all]                       - Show usage statistics"
		di as text "  {cmd:registream uninstall} [all|registream|autolabel|datamirror]"
		di as text "                                                       - Uninstall packages"
		di as text ""
		di as text "See {help registream:help registream} for details"
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return scalar status = 1
		exit 198
	}
	else {
		di as error "Unknown subcommand: `subcmd'"
		di as text "Available: update, info, config, version, cite, stats, uninstall"
		di as text "See {help registream:help registream} for details"
		_registream_wrapper_end "`REGISTREAM_VERSION'" "`registream_dir'" `"`0'"'
		return scalar status = 1
		exit 198
	}
end

* =============================================================================
* Subcommand: registream update
* =============================================================================
program define _registream_update
	version 16.0

	* Get version from helper function
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	* Parse arguments: [package|dataset|datasets] [, domain() lang() version()]
	syntax [anything] [, DOMAIN(string) LANG(string) VERSION(string)]
	local what "`anything'"

	* Normalize domain and lang to lowercase immediately (case-insensitive)
	if ("`domain'" != "") local domain = lower("`domain'")
	if ("`lang'" != "") local lang = lower("`lang'")

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	* Initialize config (ensures it exists)
	_rs_config init "`registream_dir'"

	* If no argument or "package", check package updates
	if ("`what'" == "" | "`what'" == "package") {
		di as result ""
		di as result "{hline 60}"
		di as result "RegiStream Package Update Check"
		di as result "{hline 60}"
		di as result ""

		* Check for package updates (pass hardcoded version)
		_rs_updates check_package "`registream_dir'" "`REGISTREAM_VERSION'"
		local update_available = r(update_available)
		local current_version = r(current_version)
		local latest_version = r(latest_version)
		local reason = r(reason)

		if ("`reason'" == "internet_disabled") {
			di as text "Update check disabled (offline mode)"
			di as text "To enable: registream config, internet_access(true)"
		}
		else if ("`reason'" == "network_error") {
			di as text "Could not check for updates (network error)"
		}
		else if ("`reason'" == "success") {
			di as text "Current version: {result:`current_version'}"
			di as text "Latest version:  {result:`latest_version'}"
			di as text ""

			if (`update_available' == 1) {
				di as result "A new version is available!"
				di as text ""
				di as text "Would you like to update now? (y/n)"
				di as input "> " _request(user_response)
				local user_response = trim(lower(`"`r(user_response)'"'))

				if ("`user_response'" == "y" | "`user_response'" == "yes") {
					di as text ""
					di as result "Updating RegiStream..."
					di as text "{hline 60}"

					* Resolve install URL via dev-override-aware helper so
					* `do test_manual.do` flows install from localhost:5000.
					_rs_utils get_install_url
					local install_url "`r(url)'"

					* Detect which of our packages currently have a TRK entry,
					* then ensure `registream` is in the reinstall set. Under
					* the decoupled packaging model, core is a prerequisite
					* for every module; users on the old self-bundled scheme
					* have their `autolabel` TRK entry owning core files, so
					* an uninstall-reinstall cycle would strand them without
					* core unless we explicitly add `registream` here.
					_rs_utils detect_installed_trk_packages
					local installed_pkgs "`r(packages)'"
					if ("`installed_pkgs'" == "") {
						* First-time install via `registream update' — treat
						* as a core-only install. Modules installed separately
						* on demand.
						local installed_pkgs "registream"
					}
					if (strpos(" `installed_pkgs' ", " registream ") == 0) {
						local installed_pkgs "registream `installed_pkgs'"
					}

					foreach p of local installed_pkgs {
						cap ado uninstall `p'
					}

					local all_ok = 1
					foreach p of local installed_pkgs {
						cap noi net install `p', from("`install_url'") replace
						if (_rc != 0) local all_ok = 0
					}

					if (`all_ok' == 1) {
						di as text "{hline 60}"
						di as result "✓ Update successful!"
						di as text ""
						di as text "Reinstalled: `installed_pkgs'"
						di as text "Please restart Stata or reload the package to use the new version"
					}
					else {
						di as text "{hline 60}"
						di as error "✗ Update failed"
						di as text ""
						di as text "Please try updating manually:"
						di as text `"  cap ado uninstall registream"'
						di as text `"  net install registream, from("https://registream.org/install/stata/latest") replace"'
					}
				}
				else {
					di as text ""
					di as text "Update cancelled. To update later, run:"
					di as text "  . registream update package"
					di as text ""
					di as text "Or update manually:"
					di as text `"  . cap ado uninstall registream"'
					di as text `"  . net install registream, from("https://registream.org/install/stata/latest") replace"'
				}
			}
			else {
				di as result "You have the latest version!"
			}
		}

		di as result ""
		di as result "{hline 60}"
		di as result ""
	}

	else {
		di as error "Unknown update target: `what'"
		di as text "Usage: registream update [package]  (default: package)"
		di as text "For dataset updates, use: autolabel update datasets"
		exit 198
	}
end

* =============================================================================
* Subcommand: registream info
* =============================================================================
program define _registream_info
	version 16.0

	* Get version from helper function
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	* Initialize config (ensures it exists)
	_rs_config init "`registream_dir'"

	* Get config values (with defaults if config is read-only)
	_rs_config get "`registream_dir'" "usage_logging"
	local usage_logging = r(value)
	if ("`usage_logging'" == "") local usage_logging "true"

	_rs_config get "`registream_dir'" "telemetry_enabled"
	local telemetry = r(value)
	if ("`telemetry'" == "") local telemetry "false"

	_rs_config get "`registream_dir'" "internet_access"
	local internet = r(value)
	if ("`internet'" == "") local internet "true"

	_rs_config get "`registream_dir'" "auto_update_check"
	local auto_update = r(value)
	if ("`auto_update'" == "") local auto_update "true"

	_rs_config get "`registream_dir'" "dm_min_cell_size"
	local dm_min_cell = r(value)
	if ("`dm_min_cell'" == "") local dm_min_cell "50"

	_rs_config get "`registream_dir'" "dm_quantile_trim"
	local dm_qt = r(value)
	if ("`dm_qt'" == "") local dm_qt "1"

	* Display info
	di as result ""
	di as result "{hline 60}"
	di as result "RegiStream Configuration"
	di as result "{hline 60}"
	di as text "Directory:        {result:`registream_dir'}"
	di as text "Config file:      {result:`registream_dir'/config_stata.csv}"
	di as text ""
	di as text "Package:"
	di as text "  version:         {result:`REGISTREAM_VERSION'}"
	di as text ""
	di as text "Settings:"
	di as text "  usage_logging:       {result:`usage_logging'} (local only, stays on your machine)"
	di as text "  telemetry_enabled:   {result:`telemetry'} (sends anonymized data to registream.org)"
	di as text "  internet_access:     {result:`internet'}"
	di as text "  auto_update_check:   {result:`auto_update'}"
	di as text "  dm_min_cell_size:    {result:`dm_min_cell'} (datamirror minimum cell size for privacy suppression)"
	di as text "  dm_quantile_trim:    {result:`dm_qt'} (datamirror quantile trim percent for continuous SDC)"
	di as text ""
	di as text "Change any setting with: {bf:registream config, <key>(<value>)}"
	di as result "{hline 60}"
	di as text ""
	di as text "Citation:"
	di as text "  Clark, J. & Wen, J. (2024). RegiStream:"
	di as text "  Infrastructure for Register Data Research. https://registream.org"
	di as text ""
	di as text "Full citation (with version & datasets): {stata registream cite:registream cite}"
	di as result ""
end

* =============================================================================
* Subcommand: registream config
* =============================================================================
program define _registream_config
	version 16.0

	syntax [, USAGE_logging(string) TELEMETRY_enabled(string) INTERNET_access(string) AUTO_update_check(string) dm_min_cell_size(integer -1) dm_quantile_trim(real -1)]

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	* Initialize config
	_rs_config init "`registream_dir'"

	* If no options, just show config
	if ("`usage_logging'" == "" & "`telemetry_enabled'" == "" & "`internet_access'" == "" & "`auto_update_check'" == "" & `dm_min_cell_size' < 0 & `dm_quantile_trim' < 0) {
		_registream_info
		exit 0
	}

	* Probe writability once before touching any setting. One check covers
	* every setting in this command (plus any added later) and keeps the
	* failure message out of background bookkeeping writers (_rs_updates,
	* autolabel update checks) that wrap their own _rs_config set in cap.
	tempname __rs_probe
	cap file open `__rs_probe' using "`registream_dir'/config_stata.csv", write append
	if (_rc != 0) {
		di as error "Cannot write config: `registream_dir'/config_stata.csv is read-only."
		di as text  "Point RegiStream at a writable directory with:"
		di as text  "  {bf:global registream_dir \"/path/you/own\"}"
		exit 198
	}
	cap file close `__rs_probe'

	* Update usage_logging if provided
	if ("`usage_logging'" != "") {
		if (!inlist("`usage_logging'", "true", "false")) {
			di as error "usage_logging must be 'true' or 'false'"
			exit 198
		}
		_rs_config set "`registream_dir'" "usage_logging" "`usage_logging'"
		di as result "✓ usage_logging set to: `usage_logging'"
	}

	* Update telemetry_enabled if provided
	if ("`telemetry_enabled'" != "") {
		if (!inlist("`telemetry_enabled'", "true", "false")) {
			di as error "telemetry_enabled must be 'true' or 'false'"
			exit 198
		}
		_rs_config set "`registream_dir'" "telemetry_enabled" "`telemetry_enabled'"
		di as result "✓ telemetry_enabled set to: `telemetry_enabled'"
	}

	* Update internet_access if provided
	if ("`internet_access'" != "") {
		if (!inlist("`internet_access'", "true", "false")) {
			di as error "internet_access must be 'true' or 'false'"
			exit 198
		}
		_rs_config set "`registream_dir'" "internet_access" "`internet_access'"
		di as result "✓ internet_access set to: `internet_access'"
	}

	* Update auto_update_check if provided
	if ("`auto_update_check'" != "") {
		if (!inlist("`auto_update_check'", "true", "false")) {
			di as error "auto_update_check must be 'true' or 'false'"
			exit 198
		}
		_rs_config set "`registream_dir'" "auto_update_check" "`auto_update_check'"
		di as result "✓ auto_update_check set to: `auto_update_check'"
	}

	* Update dm_min_cell_size if provided (datamirror privacy suppression threshold)
	if (`dm_min_cell_size' >= 0) {
		if (`dm_min_cell_size' < 1) {
			di as error "dm_min_cell_size must be a positive integer"
			exit 198
		}
		_rs_config set "`registream_dir'" "dm_min_cell_size" "`dm_min_cell_size'"
		di as result "✓ dm_min_cell_size set to: `dm_min_cell_size'"
	}

	* Update dm_quantile_trim if provided (datamirror continuous SDC threshold, percent)
	if (`dm_quantile_trim' >= 0) {
		if (`dm_quantile_trim' > 50) {
			di as error "dm_quantile_trim must be between 0 and 50 (percent)"
			exit 198
		}
		_rs_config set "`registream_dir'" "dm_quantile_trim" "`dm_quantile_trim'"
		di as result "✓ dm_quantile_trim set to: `dm_quantile_trim'"
		if (`dm_quantile_trim' == 0) {
			di as text "  Note: quantile_trim(0) stores raw max/min in q0/q100." ///
				" Set only if the data were top/bottom-coded upstream."
		}
	}

	di as text ""
	di as text "Config updated successfully!"
	di as text ""
end

* =============================================================================
* Subcommand: registream version
* =============================================================================
program define _registream_version
	version 16.0

	* Get version from helper function
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	di as result ""
	di as text "RegiStream version {result:`REGISTREAM_VERSION'}"
	di as result ""
end

* =============================================================================
* Subcommand: registream cite
* =============================================================================
program define _registream_cite
	version 16.0

	* Get version from helper function
	_rs_utils get_version
	local REGISTREAM_VERSION "`r(version)'"

	* Get registream directory for dataset versions
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	di as result ""
	di as result "{hline 60}"
	di as result "Citation"
	di as result "{hline 60}"
	di as text ""
	di as text "To cite RegiStream in publications, please use:"
	di as text ""
{{CITATION_REGISTREAM_ADO_CITE_BLOCK}}
	di as text ""

	* Show installed dataset versions for reproducibility. One line per
	* unique (domain, version) pair; datasets.csv has one row per cached
	* file (variables/values/scope/... × language), so we dedup up to the
	* level users care about. Each line ends with the catalog URL so users
	* can look up provider attribution, source links, and version history.
	di as text "Installed datasets:"
	di as text ""

	* Check for datasets.csv in autolabel directory
	local autolabel_dir "`registream_dir'/autolabel"
	local datasets_csv "`autolabel_dir'/datasets.csv"
	cap confirm file "`datasets_csv'"
	if (_rc == 0) {
		* Read datasets.csv line by line
		tempname fh
		file open `fh' using "`datasets_csv'", read
		file read `fh' line

		* Skip header line
		file read `fh' line

		* Columns: dataset_key;domain;type;lang;version;schema;downloaded;source;file_size;last_checked
		local seen_pairs ""
		local found_any = 0
		while r(eof)==0 {
			local dataset_domain = trim(word(subinstr("`line'", ";", " ", .), 2))
			local dataset_version = trim(word(subinstr("`line'", ";", " ", .), 5))

			if ("`dataset_domain'" != "" & "`dataset_version'" != "") {
				local pair "`dataset_domain'|`dataset_version'"
				if (strpos(" `seen_pairs' ", " `pair' ") == 0) {
					local seen_pairs "`seen_pairs' `pair'"
					di as text "  • `dataset_domain' v`dataset_version': https://registream.org/catalog/`dataset_domain'"
					local found_any = 1
				}
			}

			file read `fh' line
		}
		file close `fh'

		if (`found_any' == 0) {
			di as text "  (none installed yet)"
		}
	}
	else {
		di as text "  (none installed yet)"
	}

	di as result ""
	di as result "{hline 60}"
	di as result ""
end

* =============================================================================
* Subcommand: registream stats
* =============================================================================
program define _registream_stats
	* Parse optional "all" argument
	local all_flag ""
	if (trim("`0'") == "all" | trim("`0'") == ", all") {
		local all_flag "all"
	}

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"

	* Initialize usage tracking (ensures config exists)
	_rs_usage init "`registream_dir'"

	* Display stats
	if ("`all_flag'" != "") {
		_rs_usage stats "`registream_dir'" all
	}
	else {
		_rs_usage stats "`registream_dir'"
	}
end

* =============================================================================
* Subcommand: registream uninstall [all|<module>]
*
* Decoupled packaging (one TRK entry per package) makes selective uninstall
* trivial — `ado uninstall X` just works when X is a real TRK entry. This
* helper wraps the dance with (a) argument validation, (b) a report of what
* remains so users can decide if they want to remove more, and (c) a warning
* when core is removed while modules are still installed.
* =============================================================================
program define _registream_uninstall
	args what

	if ("`what'" == "") {
		di as error "Missing argument. Specify what to uninstall:"
		di as text "  {cmd:registream uninstall all}          - remove everything"
		di as text "  {cmd:registream uninstall registream}   - remove core only"
		di as text "  {cmd:registream uninstall autolabel}    - remove autolabel only"
		di as text "  {cmd:registream uninstall datamirror}   - remove datamirror only"
		exit 198
	}

	if (!inlist("`what'", "all", "registream", "autolabel", "datamirror")) {
		di as error "Unknown uninstall target: `what'"
		di as error "Valid: all, registream, autolabel, datamirror"
		exit 198
	}

	* Snapshot current installation state from STATA.TRK.
	_rs_utils detect_installed_trk_packages
	local installed "`r(packages)'"

	if ("`installed'" == "") {
		di as text "No RegiStream packages are installed."
		exit 0
	}

	if ("`what'" == "all") {
		* Remove modules first, core last, so core isn't needed during
		* the module `ado uninstall` call.
		foreach p in autolabel datamirror registream {
			if (strpos(" `installed' ", " `p' ") > 0) {
				di as text "Uninstalling `p'..."
				cap noi ado uninstall `p'
			}
		}
		di as result ""
		di as result "{hline 60}"
		di as result "✓ All RegiStream packages uninstalled."
		di as result "{hline 60}"
		exit 0
	}

	* Single-package uninstall
	if (strpos(" `installed' ", " `what' ") == 0) {
		di as error "`what' is not installed."
		di as text "Installed packages: `installed'"
		exit 111
	}

	di as text "Uninstalling `what'..."
	cap noi ado uninstall `what'
	if (_rc != 0) {
		di as error "✗ Uninstall of `what' failed (rc=`=_rc')."
		exit _rc
	}

	di as result "✓ Uninstalled `what'."

	* Refresh installed-list and report what's left.
	_rs_utils detect_installed_trk_packages
	local remaining "`r(packages)'"

	di as text ""
	if ("`remaining'" == "") {
		di as text "No RegiStream packages remain installed."
	}
	else {
		di as text "Remaining packages: `remaining'"
		di as text ""
		di as text "  {cmd:registream uninstall all}          - remove everything"
		di as text "  {cmd:registream uninstall <name>}       - remove individually"
	}

	* Warn if core was removed while modules remain. Those modules will
	* error out on first invocation via their runtime `cap findfile' check.
	if ("`what'" == "registream" & "`remaining'" != "") {
		di as text ""
		di as error "Warning: registream core was removed, but these modules remain:"
		di as error "    `remaining'"
		di as error "They will error at runtime until registream is reinstalled:"
		di as error `"  net install registream, from("https://registream.org/install/stata/latest") replace"'
	}
end

* =============================================================================
* MASTER WRAPPER FUNCTIONS
* =============================================================================

* Wrapper start: Initialize everything + log usage + background check
program define _registream_wrapper_start, rclass
	* gettoken preserves inner quotes in command_line
	gettoken current_version 0 : 0
	gettoken command_line 0 : 0

	* Get registream directory
	_rs_utils get_dir
	local registream_dir "`r(dir)'"
	return local registream_dir "`registream_dir'"

	* Initialize config
	_rs_config init "`registream_dir'"

	* Parse command for conditional logic
	local first_word : word 1 of `command_line'

	* Log local usage (fast, synchronous) - skip "stats" to avoid recursion.
	* usage_stata.csv is the source of truth for the batch; wrapper_end's
	* heartbeat reads rows with timestamp > last_update_check. No session
	* global is needed (matches Python _read_usage_since / R read_pending_usage).
	if ("`first_word'" != "stats") {
		_rs_config get "`registream_dir'" "usage_logging"
		if (r(value) == "true" | r(value) == "1") {
			_rs_usage init "`registream_dir'"
			_rs_usage log "`registream_dir'" `"registream `command_line'"' "registream" "`current_version'" "`current_version'"
		}
	}

	* NOTE: Telemetry and update check moved to wrapper_end for consolidated heartbeat
	* This ensures instant startup with no blocking on network operations
end

* Wrapper end: Consolidated heartbeat (telemetry + update check) + notification
program define _registream_wrapper_end
	gettoken current_version 0 : 0
	gettoken registream_dir 0 : 0
	gettoken command_line 0 : 0

	* If `registream uninstall all` just removed core, the helper .ado
	* files are gone from disk. Skip wrapper_end entirely — there is
	* nothing to report and any _rs_config lookup would fail.
	cap findfile _rs_config.ado
	if _rc != 0 exit 0

	* Get registream directory if not provided
	if ("`registream_dir'" == "") {
		_rs_utils get_dir
		local registream_dir "`r(dir)'"
	}

	* Parse command for conditional logic
	if ("`command_line'" != "") {
		gettoken first_word rest : command_line, parse(" ,")
	}

	* Check if we should send heartbeat (telemetry OR update check enabled)
	_rs_config get "`registream_dir'" "telemetry_enabled"
	local telemetry_enabled = r(value)
	_rs_config get "`registream_dir'" "internet_access"
	local internet_access = r(value)
	_rs_config get "`registream_dir'" "auto_update_check"
	local auto_update_enabled = r(value)

	* Default to true if not found
	if ("`auto_update_enabled'" == "") local auto_update_enabled "true"

	* Send heartbeat if: (telemetry OR update_check) AND internet AND not "update"/"stats"/"config" command
	local should_heartbeat = 0
	if (("`telemetry_enabled'" == "true" | "`telemetry_enabled'" == "1" | "`auto_update_enabled'" == "true" | "`auto_update_enabled'" == "1") & ("`internet_access'" == "true" | "`internet_access'" == "1") & "`first_word'" != "update" & "`first_word'" != "stats" & "`first_word'" != "config") {
		local should_heartbeat = 1
	}

	* Detect which modules are installed so the meta-command heartbeat can
	* ask the server about every module, not just the ones touched this
	* session (parity with Python _installed_version / R installed_version).
	local al_ver ""
	local dm_ver ""
	cap _rs_utils detect_installed_modules
	if (_rc == 0) {
		local al_ver "`r(autolabel_version)'"
		local dm_ver "`r(datamirror_version)'"
	}

	local core_update 0
	local core_latest ""
	local al_update 0
	local al_latest ""
	local dm_update 0
	local dm_latest ""

	if (`should_heartbeat' == 1) {
		* Positional args: dir ver cmd module module_version al_ver dm_ver
		cap qui _rs_updates send_heartbeat "`registream_dir'" "`current_version'" ///
			`"registream `command_line'"' "" "" "`al_ver'" "`dm_ver'"
		local core_update = r(update_available)
		local core_latest "`r(latest_version)'"
		local al_update = r(autolabel_update)
		local al_latest "`r(autolabel_latest)'"
		local dm_update = r(datamirror_update)
		local dm_latest "`r(datamirror_latest)'"
	}

	* Show update notification if available; core scope includes all modules
	* so `registream update` surfaces autolabel and datamirror updates too.
	_rs_updates show_notification , ///
		current_version("`current_version'") scope(core) ///
		core_update(`core_update') core_latest("`core_latest'") ///
		autolabel_update(`al_update') autolabel_latest("`al_latest'") ///
		datamirror_update(`dm_update') datamirror_latest("`dm_latest'")
end
