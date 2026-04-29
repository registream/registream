* =============================================================================
* RegiStream Utility Functions
* Shared helper functions used across all RegiStream modules
* Usage: _rs_utils subcommand [args]
* =============================================================================

program define _rs_utils, rclass
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "get_dir") {
		_utils_get_dir `0'
		return add
	}
	else if ("`subcmd'" == "confirmdir") {
		_utils_confirmdir `0'
		return add
	}
	else if ("`subcmd'" == "escape_ascii") {
		_utils_escape_ascii `0'
		return add
	}
	else if ("`subcmd'" == "del_folder_rec") {
		_utils_del_folder_rec `0'
	}
	else if ("`subcmd'" == "mkdir_p") {
		_utils_mkdir_p `0'
	}
	else if ("`subcmd'" == "get_api_host") {
		_utils_get_api_host `0'
		return add
	}
	else if ("`subcmd'" == "get_install_url") {
		_utils_get_install_url `0'
		return add
	}
	else if ("`subcmd'" == "prompt") {
		_utils_prompt `0'
		return add
	}
	else if ("`subcmd'" == "prompt_choice") {
		_utils_prompt_choice `0'
		return add
	}
	else if ("`subcmd'" == "get_version") {
		_utils_get_version `0'
		return add
	}
	else if ("`subcmd'" == "get_filesize") {
		_utils_get_filesize `0'
		return add
	}
	else if ("`subcmd'" == "detect_installed_modules") {
		_utils_detect_modules `0'
		return add
	}
	else if ("`subcmd'" == "detect_installed_trk_packages") {
		_utils_detect_trk_packages `0'
		return add
	}
	else if ("`subcmd'" == "get_core_version") {
		_utils_get_core_version `0'
		return add
	}
	else if ("`subcmd'" == "check_core_version") {
		_utils_check_core_version `0'
		return add
	}
	else {
		di as error "Invalid _rs_utils subcommand: `subcmd'"
		exit 198
	}
end

* -----------------------------------------------------------------------------
* get_dir: Get RegiStream directory path
* Returns r(dir) with the registream directory path
* -----------------------------------------------------------------------------
program define _utils_get_dir, rclass
	* Check if we have $registream_dir override
	if "$registream_dir" != "" {
		return local dir "$registream_dir"
		exit 0
	}

	* Detect the operating system and set the path
	local os = c(os)
	local machine = c(machine_type)
	local username = c(username)

	* Check for Mac first (handles both interactive "MacOSX" and batch mode "Unix" with Macintosh machine)
	if strpos("`machine'", "Macintosh") > 0 | "`os'" == "MacOSX" {
		local homedir "/Users/`username'"
		local registream_dir "`homedir'/.registream"
	}
	else if "`os'" == "Windows" {
		local homedir "C:/Users/`username'"
		local registream_dir "`homedir'/AppData/Local/registream"
	}
	else if "`os'" == "Unix" {
		* Linux (Unix but not Macintosh)
		local homedir "/home/`username'"
		local registream_dir "`homedir'/.registream"
	}
	else {
		di as error "Cannot determine RegiStream directory for OS: `os', machine: `machine'"
		exit 1
	}

	return local dir "`registream_dir'"
end

* -----------------------------------------------------------------------------
* confirmdir: Check if a directory exists
* Returns r(exists) = 1 if directory exists, 0 otherwise
* -----------------------------------------------------------------------------
program define _utils_confirmdir, rclass
	syntax anything(name=arguments)

	* Extract the first word from namelist (should be the directory path)
	local check_path : word 1 of `arguments'
	local syntax_check : subinstr local arguments "`check_path'" "", all

	* Check if more than one argument was passed
	if "`syntax_check'" != "" {
		di as error "Invalid syntax: pass just one argument, i.e., the filepath."
		exit 198
	}

	local original_dir "`c(pwd)'"

	* Try to change the directory to see if the path exists
	cap cd "`check_path'"

	* Set return value based on the success of changing the directory
	if (_rc == 0) {
		* Directory exists
		qui cd "`original_dir'"
		return scalar exists = 1
	}
	else {
		* Directory does not exist
		return scalar exists = 0
	}
end

* -----------------------------------------------------------------------------
* escape_ascii: Escape special characters in strings
* Returns r(escaped_string) with escaped string
* -----------------------------------------------------------------------------
program define _utils_escape_ascii, rclass
	args input_string

	* Escape special characters by replacing them with q followed by ASCII code
	local escaped = "`input_string'"
	local escaped = subinstr("`escaped'", ".", "q46", .)
	local escaped = subinstr("`escaped'", "*", "q42", .)
	local escaped = subinstr("`escaped'", "/", "q47", .)
	local escaped = subinstr("`escaped'", "&", "q38", .)
	local escaped = subinstr("`escaped'", "-", "q45", .)
	local escaped = subinstr("`escaped'", "_", "q95", .)
	local escaped = subinstr("`escaped'", "[", "q91", .)
	local escaped = subinstr("`escaped'", "]", "q93", .)
	local escaped = subinstr("`escaped'", "{", "q123", .)
	local escaped = subinstr("`escaped'", "}", "q125", .)
	local escaped = subinstr("`escaped'", " ", "q32", .)

	* Return the escaped string
	return local escaped_string "`escaped'"
end

* -----------------------------------------------------------------------------
* mkdir_p: Recursive mkdir (native, no shell).
* Creates `path' and any missing parent directories. Idempotent: returns 0
* when the directory already exists or is newly created; non-zero on genuine
* failure (invalid path, permissions).
*
* Why native: `shell mkdir -p` flashes a cmd window on Windows and breaks
* silent-batch assumptions. Stata's native `mkdir` is single-level, so we
* recurse: on rc=602 (parent missing), find the deepest separator, recurse
* on the parent, then retry. Handles both / and \\ separators (Windows
* accepts either). Used by modules (datamirror's checkpoint_dir, any
* package with arbitrary-depth paths); autolabel's cache is shallow and
* uses single-level mkdirs in place.
*
* Usage: _rs_utils mkdir_p "path/to/nested/dir"
* -----------------------------------------------------------------------------
program _utils_mkdir_p
	args path

	cap mkdir "`path'"
	if _rc == 0 | _rc == 693 exit 0

	if _rc == 602 {
		local last_fwd = strpos(reverse("`path'"), "/")
		local last_bwd = strpos(reverse("`path'"), "\")
		if `last_fwd' == 0 & `last_bwd' == 0 exit 602

		if `last_fwd' == 0 {
			local last_sep = `last_bwd'
		}
		else if `last_bwd' == 0 {
			local last_sep = `last_fwd'
		}
		else {
			local last_sep = min(`last_fwd', `last_bwd')
		}

		local parent = substr("`path'", 1, length("`path'") - `last_sep')
		if "`parent'" == "" exit 602

		_rs_utils mkdir_p "`parent'"
		cap mkdir "`path'"
		exit _rc
	}

	exit _rc
end

* -----------------------------------------------------------------------------
* del_folder_rec: Recursively delete a folder and its contents
* -----------------------------------------------------------------------------
program _utils_del_folder_rec
	args folder

	* List all files in the current directory
	local files : dir "`folder'" files "*"

	* Delete all files in the directory
	foreach file in `files' {
		erase "`folder'/`file'"
	}

	* List all subdirectories
	local subdirs : dir "`folder'" dirs "*"

	* Recursively call the program to delete files and subdirectories
	foreach subdir in `subdirs' {
		_rs_utils del_folder_rec "`folder'/`subdir'"
	}

	* Delete the directory once all contents are removed
	rmdir "`folder'"
end

* -----------------------------------------------------------------------------
* get_api_host: Get API host (with development override support)
* Returns r(host) with the API host URL
* -----------------------------------------------------------------------------
* Priority (highest to lowest):
*   1. Dev mode: _rs_dev_utils get_host (defined in stata/dev/host_override.do)
*   2. Production: https://registream.org (hardcoded)
* -----------------------------------------------------------------------------
program define _utils_get_api_host, rclass
	* Try dev override (only defined if stata/dev/host_override.do was sourced)
	cap qui _rs_dev_utils get_host
	if (_rc == 0) {
		return local host "`r(host)'"
	}
	else {
		* Production: HARDCODED value (ONE location)
		return local host "https://registream.org"
	}
end

* -----------------------------------------------------------------------------
* get_install_url: Get the canonical net install URL (with dev override support)
* Returns r(url): single source of truth for `net install ... from(...)`
*
* Examples:
*   production : https://registream.org/install/stata/latest
*   dev override: http://localhost:5000/install/stata/latest
* -----------------------------------------------------------------------------
program define _utils_get_install_url, rclass
	_utils_get_api_host
	return local url "`r(host)'/install/stata/latest"
end

* -----------------------------------------------------------------------------
* prompt: Display interactive user prompt
* Returns r(response) = "yes"
*
* Honors $REGISTREAM_AUTO_APPROVE="yes" for batch mode (set via
* stata/dev/auto_approve.do in tests; parallel to the REGISTREAM_AUTO_APPROVE
* env var in the Python client).
*
* Usage:
*   _rs_utils prompt "Download dataset from API?"
*   local response = r(response)
* -----------------------------------------------------------------------------
program define _utils_prompt, rclass
	args prompt_message

	* Check if auto-approve is enabled (dev mode or test mode)
	if ("$REGISTREAM_AUTO_APPROVE" == "yes") {
		di as text "`prompt_message' [AUTO-APPROVED]"
		return local response "yes"
		exit 0
	}

	* Display prompt and wait for user input
	di as text ""
	di as result "`prompt_message'"
	di as text "  Type 'yes' or 'no': " _request(user_response)

	* Normalize response (trim whitespace and convert to lowercase)
	local response = lower(trim("$user_response"))

	* Check for exit/quit commands (undocumented escape hatch)
	if ("`response'" == "exit" | "`response'" == "quit" | "`response'" == "q") {
		di as error ""
		di as error "Program terminated by user."
		di as error ""
		exit 1
	}

	* Validate response
	if ("`response'" != "yes" & "`response'" != "no") {
		di as error "Invalid response. Please type 'yes' or 'no'."
		di as text ""

		* Retry prompt
		_rs_utils prompt "`prompt_message'"
		return add
		exit 0
	}

	* User declined - exit with error
	if ("`response'" == "no") {
		di as error ""
		di as error "Operation cancelled by user."
		di as error ""
		exit 1
	}

	* User approved - return successfully
	return local response "yes"
end

* -----------------------------------------------------------------------------
* prompt_choice: Display numbered choice prompt
* Returns r(choice) = choice number (1, 2, 3, etc.)
*
* In batch mode ($REGISTREAM_AUTO_APPROVE="yes") auto-returns choice "1".
* Automatically appends "Abort" as the last option (exits with error if selected).
*
* Usage:
*   _rs_utils prompt_choice "What to do?" "Continue" "Re-download"
*   local choice = r(choice)
*
* Will display:
*   [1] Continue
*   [2] Re-download
*   [3] Abort
* -----------------------------------------------------------------------------
program define _utils_prompt_choice, rclass
	* First argument is the message, rest are choices
	gettoken message 0 : 0

	* Check if auto-approve is enabled (dev mode or test mode)
	if ("$REGISTREAM_AUTO_APPROVE" == "yes") {
		di as text "`message' [AUTO-APPROVED: choice 1 selected]"
		return local choice "1"
		exit 0
	}

	* Parse choices
	local num_choices 0
	while (`"`0'"' != "") {
		gettoken choice 0 : 0
		local ++num_choices
		local choice_`num_choices' `"`choice'"'
	}

	* Always add "Abort" as the last option
	local ++num_choices
	local choice_`num_choices' "Abort"
	local abort_option = `num_choices'

	* Display prompt
	di as text ""
	di as result "  `message'"
	di as text ""
	forvalues i = 1/`num_choices' {
		di as text "    [`i'] `choice_`i''"
	}
	di as text ""
	di as text "  Enter choice (1-`num_choices'): " _request(user_choice)

	* Validate choice
	local choice = lower(trim("$user_choice"))

	* Check for exit/quit commands (undocumented escape hatch)
	if ("`choice'" == "exit" | "`choice'" == "quit" | "`choice'" == "q") {
		di as error ""
		di as error "Program terminated by user."
		di as error ""
		exit 1
	}

	* Check if numeric
	cap confirm number `choice'
	if (_rc != 0) {
		di as error "Invalid choice. Please enter a number between 1 and `num_choices'."
		di as text ""

		* Rebuild argument list and retry (exclude abort option)
		local args `""`message'""'
		local original_choices = `num_choices' - 1
		forvalues i = 1/`original_choices' {
			local args `"`args' "`choice_`i''""'
		}
		_rs_utils prompt_choice `args'
		return add
		exit 0
	}

	* Check if in range
	if (`choice' < 1 | `choice' > `num_choices') {
		di as error "Invalid choice. Please enter a number between 1 and `num_choices'."
		di as text ""

		* Rebuild argument list and retry (exclude abort option)
		local args `""`message'""'
		local original_choices = `num_choices' - 1
		forvalues i = 1/`original_choices' {
			local args `"`args' "`choice_`i''""'
		}
		_rs_utils prompt_choice `args'
		return add
		exit 0
	}

	* Check if user selected Abort option
	if (`choice' == `abort_option') {
		di as error ""
		di as error "Operation aborted by user."
		di as error ""
		exit 1
	}

	return local choice "`choice'"
end

* -----------------------------------------------------------------------------
* get_version: Get RegiStream version
* Returns r(version) with the current version
* -----------------------------------------------------------------------------
* This helper function returns the current version of RegiStream.
*
* Priority (highest to lowest):
*   1. Dev mode: _rs_dev_utils get_version (defined in stata/dev/version_override.do)
*   2. Production: {{VERSION}} (hardcoded, replaced during package export)
* -----------------------------------------------------------------------------
program define _utils_get_version, rclass
	* Try dev override (only defined if stata/dev/version_override.do was sourced)
	cap qui _rs_dev_utils get_version
	if (_rc == 0) {
		* Dev override exists - return its value
		return local version "`r(version)'"
	}
	else {
		* Production: HARDCODED value (ONE location)
		return local version "{{VERSION}}"
	}
end

* -----------------------------------------------------------------------------
* get_filesize: Get file size in bytes (cross-platform)
* Returns r(size) with the file size in bytes, or 0 if file doesn't exist
* -----------------------------------------------------------------------------
* Uses Mata file I/O (fopen, fseek, ftell) which works on:
*   - Windows Server / Windows PC
*   - macOS
*   - Linux
*
* Usage:
*   _rs_utils get_filesize "/path/to/file.csv"
*   local size = r(size)
* -----------------------------------------------------------------------------
program define _utils_get_filesize, rclass
	args filepath

	quietly {
		mata: st_local("size_result", strofreal(_rs_get_filesize_mata(st_local("filepath"))))
	}

	return scalar size = `size_result'
end

* -----------------------------------------------------------------------------
* get_core_version: Read the installed core version from registream.ado.
*
* Public surface: `_rs_utils get_core_version` (callers must route through
* the dispatcher because Stata's autoloader only registers the program that
* matches the filename — nested programs aren't directly autoloadable from
* outside the file).
*
* Returns r(version) by parsing the `*! version X.Y.Z YYYY-MM-DD` header
* of registream.ado on the adopath. Returns r(version) = "" if the file
* is unreachable or unreadable (caller should treat that as core-missing).
*
* Pattern matches _utils_detect_modules — single source of truth for how
* a Stata package's installed version is read.
* -----------------------------------------------------------------------------
program define _utils_get_core_version, rclass
	return local version ""

	* Dev override first (honors $REGISTREAM_TEST_VERSION when
	* stata/dev/version_override.do has been sourced).
	cap qui _rs_dev_utils get_version
	if (_rc == 0 & "`r(version)'" != "") {
		return local version "`r(version)'"
		exit 0
	}

	cap qui findfile registream.ado
	if (_rc != 0) exit 0

	local path "`r(fn)'"
	tempname fh
	cap file open `fh' using "`path'", read text
	if (_rc != 0) exit 0

	file read `fh' firstline
	file close `fh'
	if (regexm(`"`firstline'"', "^\*! version ([0-9][^ ]*)")) {
		return local version = regexs(1)
	}
end

* -----------------------------------------------------------------------------
* check_core_version: Verify core is new enough for a calling module.
*
* Public surface: `_rs_utils check_core_version "<module>" "<min_version>"`.
* Callers must route through the dispatcher (see get_core_version note).
*
* Args (positional):
*   1. module_name  — caller's module name, used in the error message
*                     (e.g., "autolabel", "datamirror")
*   2. min_version  — minimum required core version (e.g., "3.0.1")
*
* Returns r(core_version) on success. On failure exits 198 with a clear
* upgrade-instruction banner. If core is missing entirely, the caller's
* `findfile _rs_utils.ado` check should have caught it first; this
* function still degrades gracefully (treats unreadable as too-old).
*
* See registream-docs/architecture/version_coordination.md for the
* cross-client design.
* -----------------------------------------------------------------------------
program define _utils_check_core_version, rclass
	args module_name required_version

	if ("`module_name'" == "" | "`required_version'" == "") {
		di as error "_rs_utils check_core_version requires (module_name, min_version)"
		exit 198
	}

	* Read the installed core version from registream.ado's header.
	_utils_get_core_version
	local core_version "`r(version)'"

	* --- Parse core version into major.minor.patch ---
	local work "`core_version'"
	gettoken core_major work : work, parse(".")
	gettoken dot work : work, parse(".")
	gettoken core_minor work : work, parse(".")
	gettoken dot work : work, parse(".")
	local core_patch "`work'"

	* --- Parse required version into major.minor.patch ---
	local work "`required_version'"
	gettoken req_major work : work, parse(".")
	gettoken dot work : work, parse(".")
	gettoken req_minor work : work, parse(".")
	gettoken dot work : work, parse(".")
	local req_patch "`work'"

	* Treat empty/garbage core_version as too-old (zeros lose every compare).
	if ("`core_major'" == "") local core_major 0
	if ("`core_minor'" == "") local core_minor 0
	if ("`core_patch'" == "") local core_patch 0

	* --- Compare versions ---
	local too_old 0
	if (`core_major' < `req_major') {
		local too_old 1
	}
	else if (`core_major' == `req_major') {
		if (`core_minor' < `req_minor') {
			local too_old 1
		}
		else if (`core_minor' == `req_minor') {
			if (`core_patch' < `req_patch') {
				local too_old 1
			}
		}
	}

	if (`too_old') {
		di as error "`module_name' requires registream core >= `required_version'."
		if ("`core_version'" != "") {
			di as error "You have core version `core_version'."
		}
		else {
			di as error "Core is not installed (or its version header is unreadable)."
		}
		di as error `"Run:  cap ado uninstall registream"'
		di as error `"      net install registream, from("https://registream.org/install/stata/registream/latest") replace"'
		exit 198
	}

	return local core_version "`core_version'"
end

* -----------------------------------------------------------------------------
* detect_installed_modules: Probe adopath for module .ado files and extract
* their version from the `*! version X.Y.Z YYYY-MM-DD' header line.
*
* Matches Python's importlib.metadata.version() / R's packageVersion(): gives
* the heartbeat URL builder a way to report every installed module without
* relying on session globals set by the module's first-call side effect.
*
* Returns (rclass):
*   r(autolabel_version)   "" if not installed, else the header version
*   r(datamirror_version)  "" if not installed, else the header version
* -----------------------------------------------------------------------------
program define _utils_detect_modules, rclass
	return local autolabel_version ""
	return local datamirror_version ""

	foreach m in autolabel datamirror {
		cap qui findfile `m'.ado
		if (_rc == 0) {
			local path "`r(fn)'"
			local ver ""
			tempname fh
			cap file open `fh' using "`path'", read text
			if (_rc == 0) {
				file read `fh' firstline
				file close `fh'
				if (regexm(`"`firstline'"', "^\*! version ([0-9][^ ]*)")) {
					local ver = regexs(1)
				}
			}
			return local `m'_version "`ver'"
		}
	}
end

* -----------------------------------------------------------------------------
* detect_installed_trk_packages: List which of our packages currently have
* a STATA.TRK entry, by name. Uses `ado dir` (the official interface) rather
* than parsing STATA.TRK directly.
*
* Returns r(packages) = space-separated package names from
* {registream, autolabel, datamirror} that are installed in the tracker.
*
* Why this matters: each module's .pkg bundles core files under the module's
* TRK name, so a user who ran `net install autolabel` has NO `registream`
* TRK entry. The old `registream update` flow blindly `ado uninstall`ed all
* three names and failed silently on the ones that don't exist. This helper
* lets us operate only on the entries that are actually there.
* -----------------------------------------------------------------------------
program define _utils_detect_trk_packages, rclass
	return local packages ""

	* Parse STATA.TRK directly — more reliable than routing `ado dir` output
	* through a log channel (which interacts poorly with Stata's batch-mode
	* default log). STATA.TRK is plain text at a fixed path; each package
	* entry has an `N <name>.pkg` line as its identifier.
	local trk_path "`c(sysdir_plus)'stata.trk"
	cap confirm file "`trk_path'"
	if (_rc != 0) exit 0

	tempname fh
	cap file open `fh' using "`trk_path'", read text
	if (_rc != 0) exit 0

	local found ""
	file read `fh' line
	while (r(eof) == 0) {
		if (regexm(`"`line'"', "^N (registream|autolabel|datamirror)\.pkg$")) {
			local pkg = regexs(1)
			if (strpos(" `found' ", " `pkg' ") == 0) {
				local found "`found' `pkg'"
			}
		}
		file read `fh' line
	}
	file close `fh'

	return local packages = trim("`found'")
end

* Define Mata function for file size
mata:
real scalar _rs_get_filesize_mata(string scalar filepath)
{
	real scalar fh, size, ch
	string scalar line

	fh = _fopen(filepath, "r")
	if (fh < 0) {
		return(0)
	}

	// Count bytes by reading file
	size = 0
	while ((line = fget(fh)) != J(0,0,"")) {
		size = size + strlen(line) + 1  // +1 for newline
	}

	fclose(fh)

	return(size)
}
end
