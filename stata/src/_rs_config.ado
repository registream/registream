program define _rs_config, rclass
	version 16.0
	* CSV config file management for RegiStream

	gettoken subcmd 0 : 0

	if ("`subcmd'" == "init") {
		_config_init `0'
		return add
	}
	else if ("`subcmd'" == "get") {
		_config_get `0'
		return add
	}
	else if ("`subcmd'" == "set") {
		_config_set `0'
		return add
	}
	else if ("`subcmd'" == "path") {
		_config_path `0'
		return add
	}
	else {
		di as error "Invalid _rs_config subcommand: `subcmd'"
		exit 198
	}
end

* Get config file path
program define _config_path, rclass
	args dir

	local config_file "`dir'/config_stata.csv"
	return clear
	return local config_file "`config_file'"
end

* Initialize config_stata.csv if it doesn't exist
program define _config_init, rclass
	args dir

	local config_file "`dir'/config_stata.csv"

	* Check if config already exists and has valid content
	if (fileexists("`config_file'")) {
		* Verify config has required settings (check for usage_logging key)
		_rs_config get "`dir'" "usage_logging"
		local has_content = r(found)

		if (`has_content' == 1) {
			* Valid config exists
			return clear
			return scalar exists = 1
			return scalar writable = 1
			exit 0
		}
		else {
			* Empty or invalid config - delete and reinitialize
			cap erase "`config_file'"
		}
	}

	* Try to create config directory if it doesn't exist
	cap _rs_utils confirmdir "`dir'"
	if (r(exists) == 0) {
		cap mkdir "`dir'"
		if (_rc != 0) {
			* Can't create directory (read-only system)
			return clear
			return scalar exists = 0
			return scalar writable = 0
			exit 0
		}
	}

	* ═══════════════════════════════════════════════════════════════════════
	* FIRST-RUN SETUP: Get user consent for internet connections (SSC compliance)
	* ═══════════════════════════════════════════════════════════════════════

	* Default values for new config (Full Mode - for testing usage tracking)
	local usage_logging "true"
	local telemetry_enabled "true"
	local internet_access "true"
	local auto_update_check "true"
	local dm_min_cell_size "50"
	local dm_quantile_trim "1"

	* Check if auto-approve is enabled (for automated testing)
	if ("$REGISTREAM_AUTO_APPROVE" != "yes") {
		* Show first-run setup prompt
		di as result ""
		di as result "  {hline 78}"
		di as result "  Welcome to RegiStream"
		di as result "  {hline 78}"
		di as text ""
		di as text "  Config will be saved to: {result:`dir'}"
		di as text ""
		di as result "  Choose a mode:"
		di as text ""
		di as text "    1) {bf:Offline}: no internet. You manage metadata manually."
		di as text "    2) {bf:Standard}: auto-download metadata and updates. {it:Recommended.}"
		di as text "    3) {bf:Full}: Standard + share anonymous usage data to help improve RegiStream."
		di as text ""
		di as text "  You can change this anytime with {bf:registream config}."
		di as text ""

		* Get user choice (3 options)
		_rs_utils prompt_choice "Select setup mode:" "Offline Mode" "Standard Mode" "Full Mode"
		local choice = r(choice)

		if ("`choice'" == "1") {
			local usage_logging "true"
			local telemetry_enabled "false"
			local internet_access "false"
			local auto_update_check "false"
			di as text ""
			di as result "  ✓ Offline Mode"
			di as text "    Enable internet later with: {bf:registream config, internet_access(true)}"
			di as text ""
		}
		else if ("`choice'" == "2") {
			local usage_logging "true"
			local telemetry_enabled "false"
			local internet_access "true"
			local auto_update_check "true"
			di as text ""
			di as result "  ✓ Standard Mode"
			di as text ""
		}
		else {
			local usage_logging "true"
			local telemetry_enabled "true"
			local internet_access "true"
			local auto_update_check "true"
			di as text ""
			di as result "  ✓ Full Mode: thanks for helping improve RegiStream"
			di as text "    Opt out anytime with: {bf:registream config, telemetry_enabled(false)}"
			di as text ""
		}
	}
	* else: AUTO_APPROVE mode (testing) - uses Full Mode (option 3) defaults

	* ═══════════════════════════════════════════════════════════════════════
	* Create config_stata.csv with user's choices
	* ═══════════════════════════════════════════════════════════════════════

	* Try to write initial config_stata.csv
	cap file close configfile
	qui cap file open configfile using "`config_file'", write replace
	if (_rc != 0) {
		* Can't write config (read-only system)
		return clear
		return scalar exists = 0
		return scalar writable = 0
		exit 0
	}

	file write configfile "key;value" _n
	file write configfile "usage_logging;`usage_logging'" _n
	file write configfile "telemetry_enabled;`telemetry_enabled'" _n
	file write configfile "internet_access;`internet_access'" _n
	file write configfile "auto_update_check;`auto_update_check'" _n
	file write configfile "dm_min_cell_size;`dm_min_cell_size'" _n
	file write configfile "dm_quantile_trim;`dm_quantile_trim'" _n
	file write configfile "last_update_check;" _n
	file write configfile "update_available;false" _n
	file write configfile "latest_version;" _n
	file write configfile "autolabel_update_available;false" _n
	file write configfile "autolabel_latest_version;" _n
	file write configfile "datamirror_update_available;false" _n
	file write configfile "datamirror_latest_version;" _n

	cap file close configfile

	return clear
	return scalar exists = 0
	return scalar writable = 1
end

* Get a value from config
program define _config_get, rclass
	args dir key

	local config_file "`dir'/config_stata.csv"

	* Check if config exists
	if (!fileexists("`config_file'")) {
		return clear
		return local value ""
		return scalar found = 0
		exit 0
	}

	* Read config file line by line
	tempname fh
	file open `fh' using "`config_file'", read

	local found 0
	local value ""

	file read `fh' line
	local eof_status = r(eof)
	while `eof_status' == 0 {
		* Parse CSV: key;value
		local sep_pos = strpos(`"`line'"', ";")
		if (`sep_pos' > 0) {
			local line_key = substr(`"`line'"', 1, `sep_pos' - 1)
			local line_val = substr(`"`line'"', `sep_pos' + 1, .)
			if ("`line_key'" == "`key'") {
				local value "`line_val'"
				local found 1
			}
		}

		file read `fh' line
		local eof_status = r(eof)
	}

	file close `fh'

	return clear
	return local value "`value'"
	return scalar found = `found'
end

* Set a value in config (simple key-value)
* Non-fatal if config is read-only
program define _config_set, rclass
	args dir key value

	local config_file "`dir'/config_stata.csv"

	* Check if config exists
	if (!fileexists("`config_file'")) {
		* Try to init first
		_rs_config init "`dir'"
		if (r(writable) == 0) {
			* Can't write, return gracefully
			return clear
			return scalar found = 0
			return scalar writable = 0
			exit 0
		}
	}

	* Read entire file into memory
	tempname fh
	cap file open `fh' using "`config_file'", read
	if (_rc != 0) {
		* Can't read config
		return clear
		return scalar found = 0
		return scalar writable = 0
		exit 0
	}

	local lines = 0
	local found = 0

	file read `fh' line
	local eof_status = r(eof)
	while `eof_status' == 0 {
		local ++lines
		local content`lines' `"`line'"'

		* Parse CSV: check if this line's key matches
		local sep_pos = strpos(`"`line'"', ";")
		if (`sep_pos' > 0) {
			local line_key = substr(`"`line'"', 1, `sep_pos' - 1)
			if ("`line_key'" == "`key'") {
				local content`lines' "`key';`value'"
				local found = 1
			}
		}

		file read `fh' line
		local eof_status = r(eof)
	}

	file close `fh'

	* Try to write back to file
	qui cap file open `fh' using "`config_file'", write replace
	if (_rc != 0) {
		* Can't write (read-only system)
		return clear
		return scalar found = `found'
		return scalar writable = 0
		exit 0
	}

	forval i = 1/`lines' {
		file write `fh' `"`content`i''"' _n
	}

	cap file close `fh'

	return scalar found = `found'
	return scalar writable = 1
end
