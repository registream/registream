program define _rs_usage
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "init") {
		_usage_init `0'
	}
	else if ("`subcmd'" == "log") {
		_usage_log `0'
	}
	else if ("`subcmd'" == "stats") {
		_usage_stats `0'
	}
	else if ("`subcmd'" == "ensure_salt") {
		_usage_ensure_salt `0'
	}
	else if ("`subcmd'" == "compute_user_id") {
		_usage_compute_user_id `0'
	}
	else {
		di as error "Invalid _rs_usage subcommand: `subcmd'"
		exit 198
	}
end

* Initialize usage tracking (ensure config exists)
program define _usage_init
	args dir

	* Ensure config exists
	_rs_config init "`dir'"

	* Ensure salt exists (generate on first run)
	_usage_ensure_salt "`dir'"

	* Check if usage file exists, create if not
	local usage_file "`dir'/usage_stata.csv"

	local _header "timestamp;user_id;platform;module;module_version;core_version;command_string;os;platform_version"
	if (!fileexists("`usage_file'")) {
		cap file close usagefile
		quietly file open usagefile using "`usage_file'", write replace
		file write usagefile "`_header'" _n
		file close usagefile
	}
	else {
		* Rotate old-schema log (pre-module-version) to .old if header differs
		cap file close ufh
		file open ufh using "`usage_file'", read
		file read ufh firstline
		file close ufh
		if (`"`firstline'"' != `"`_header'"') {
			cap erase "`usage_file'.old"
			cap copy "`usage_file'" "`usage_file'.old"
			cap file close usagefile
			quietly file open usagefile using "`usage_file'", write replace
			file write usagefile "`_header'" _n
			file close usagefile
		}
	}
end

* Log a command usage (append to usage_stata.csv)
program define _usage_log
	* gettoken preserves inner quotes (e.g. scope("LISA" "Individer 16+"))
	gettoken dir 0 : 0
	gettoken command_string 0 : 0
	gettoken module 0 : 0
	gettoken module_version 0 : 0
	gettoken core_version 0 : 0

	* Escape stray quotes/semicolons/newlines so the CSV line stays well-formed
	local command_string = subinstr(`"`command_string'"', ";", ",", .)
	local command_string = subinstr(`"`command_string'"', `"""', "'", .)

	* Check if local usage logging is enabled
	_rs_config get "`dir'" "usage_logging"
	local enabled "`r(value)'"

	if ("`enabled'" != "true" & "`enabled'" != "1") {
		exit 0
	}

	* Get user ID (secure hash with per-installation salt)
	_usage_compute_user_id "`dir'"
	local user_id "`r(user_id)'"

	* Get current timestamp
	local timestamp "`c(current_date)'T`c(current_time)'Z"

	* Get system info (use machine type for OS to distinguish macOS from Linux in batch mode)
	local machine = c(machine_type)
	local os_raw = c(os)

	* Detect OS using same logic as _rs_utils get_dir
	if (strpos("`machine'", "Macintosh") > 0 | "`os_raw'" == "MacOSX") {
		local os "MacOSX"
	}
	else if ("`os_raw'" == "Windows") {
		local os "Windows"
	}
	else if ("`os_raw'" == "Unix") {
		local os "Unix"
	}
	else {
		local os "`os_raw'"
	}

	local platform_version "`c(stata_version)'"

	* Open usage file for appending
	local usage_file "`dir'/usage_stata.csv"

	cap file close usagefile
	file open usagefile using "`usage_file'", write append

	* Write CSV row: timestamp;user_id;platform;module;module_version;core_version;command_string;os;platform_version
	file write usagefile "`timestamp';`user_id';stata;`module';`module_version';`core_version';`command_string';`os';`platform_version'" _n

	file close usagefile

	* NOTE: Online telemetry now handled by consolidated heartbeat in wrapper_end
	* This function only handles local CSV logging
	* Usage tracking is silent - no output displayed to user
end

* Display usage statistics
program define _usage_stats
	args dir all

	local usage_file "`dir'/usage_stata.csv"

	* Check if usage file exists
	if (!fileexists("`usage_file'")) {
		di as result ""
		di as result "No usage data available yet."
		di as result "Start using RegiStream to collect statistics."
		exit 0
	}

	* Get current user ID (if not showing all)
	if ("`all'" == "") {
		* Compute secure hash (same as in _usage_log)
		_usage_compute_user_id "`dir'"
		local my_user_id "`r(user_id)'"
	}

	* Read CSV with import delimited
	quietly {
		import delimited using "`usage_file'", clear delimiter(";") varnames(1) stringcols(_all)

		local my_calls 0
		local unique_users 0
		local first_date ""
		local last_date ""

		* Count unique users
		tab user_id
		local unique_users = r(r)

		* Filter to current user if not showing all
		if ("`all'" == "") {
			keep if user_id == "`my_user_id'"
		}

		* Count calls
		local my_calls = _N

		* Get first and last dates
		if (`my_calls' > 0) {
			* Extract date from timestamp (before 'T')
			gen date_str = substr(timestamp, 1, strpos(timestamp, "T") - 1)
			sum date_str
			local first_date = date_str[1]
			local last_date = date_str[_N]
		}
	}

	* Display stats
	di as result ""
	di as result "========================================="

	if ("`all'" != "") {
		di as result "RegiStream System-Wide Statistics"
		di as result "========================================="
		di as result "Unique Users:        `unique_users'"
		di as result "Total Calls:         `my_calls'"
	}
	else {
		di as result "RegiStream Usage Statistics"
		di as result "========================================="
		di as result "Your Anonymous ID:   `my_user_id'"
		di as result "Your Total Calls:    `my_calls'"
	}

	di as result ""

	if (`my_calls' > 0 & "`first_date'" != "") {
		di as result "First Use:  `first_date'"
		di as result "Last Use:   `last_date'"
		di as result ""
	}

	if ("`all'" == "") {
		di as text "View detailed log: `usage_file'"
		di as text "Disable local logging: registream config, usage_logging(false)"
	}
	di as result "========================================="
	di as result ""
end

* Ensure salt file exists (generate random salt on first run)
program define _usage_ensure_salt, rclass
	args dir

	local salt_file "`dir'/.salt"

	* Check if salt file exists
	if (!fileexists("`salt_file'")) {
		* Generate random salt using Mata
		mata: _rs_generate_salt("`salt_file'")
	}

	return local salt_file "`salt_file'"
end

* Compute secure user ID hash using username + hostname + salt
program define _usage_compute_user_id, rclass
	args dir

	* Ensure salt exists
	_usage_ensure_salt "`dir'"
	local salt_file "`r(salt_file)'"

	* Get username and hostname
	local username "`c(username)'"
	local hostname "`c(hostname)'"

	* Read salt and compute hash in Mata
	mata: st_local("user_id", _rs_compute_secure_hash("`username'", "`hostname'", "`salt_file'"))

	return local user_id "`user_id'"
end

* ==============================================================================
* Mata functions for cryptographic hashing
* ==============================================================================

* Mata symbols persist across ado reloads (unlike programs), so drop before
* redefining to support `registream update` reinstalling in-session.
capture mata: mata drop _rs_generate_salt()
capture mata: mata drop _rs_compute_secure_hash()
capture mata: mata drop _rs_to_hex()

mata:

// Generate a random 64-character salt and save to file
void _rs_generate_salt(string scalar filename)
{
	real scalar fh, i
	string scalar salt, chars
	real scalar seed_value, char_idx

	// Use current time + random seed for entropy
	seed_value = clock(c("current_time"), "hms") + runiform(1, 1) * 1000000
	rseed(seed_value)

	// Character set for salt (alphanumeric only for safety)
	chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	salt = ""

	// Generate 64 random characters
	for (i = 1; i <= 64; i++) {
		char_idx = ceil(runiform(1, 1) * strlen(chars))
		salt = salt + substr(chars, char_idx, 1)
	}

	// Write to file
	fh = fopen(filename, "w")
	fput(fh, salt)
	fclose(fh)
}

// Compute SHA-256-inspired hash: hash(username + hostname + salt)
// Returns 16-character hexadecimal string (64-bit hash space)
string scalar _rs_compute_secure_hash(string scalar username, string scalar hostname, string scalar salt_file)
{
	real scalar fh, i, j, len
	string scalar salt, input, char
	real scalar h0, h1, h2, h3, h4, h5, h6, h7
	real scalar w, a, b, c, d, e, f, g, h, temp1, temp2
	real vector k

	// Read salt from file
	fh = fopen(salt_file, "r")
	salt = fget(fh)
	fclose(fh)

	// Concatenate inputs
	input = username + hostname + salt
	len = strlen(input)

	// Initialize hash values (SHA-256 initial values)
	h0 = 1779033703  // 0x6a09e667
	h1 = 3144134277  // 0xbb67ae85
	h2 = 1013904242  // 0x3c6ef372
	h3 = 2773480762  // 0xa54ff53a
	h4 = 1359893119  // 0x510e527f
	h5 = 2600822924  // 0x9b05688c
	h6 =  528734635  // 0x1f83d9ab
	h7 = 1541459225  // 0x5be0cd19

	// Round constants (subset of SHA-256 K constants)
	k = J(1, 16, .)
	k[1] = 1116352408;  k[2] = 1899447441;  k[3] = 3049323471;  k[4] = 3921009573
	k[5] = 961987163;   k[6] = 1508970993;  k[7] = 2453635748;  k[8] = 2870763221
	k[9] = 3624381080;  k[10] = 310598401;  k[11] = 607225278;  k[12] = 1426881987
	k[13] = 1925078388; k[14] = 2162078206; k[15] = 2614888103; k[16] = 3248222580

	// Process each character of input
	for (i = 1; i <= len; i++) {
		char = substr(input, i, 1)
		w = ascii(char)

		// Mix character into round constants
		for (j = 1; j <= 16; j++) {
			k[j] = mod(k[j] + w * 31 + i * 17, 4294967296)
		}
	}

	// Compression function (simplified SHA-256)
	a = h0; b = h1; c = h2; d = h3
	e = h4; f = h5; g = h6; h = h7

	for (j = 1; j <= 16; j++) {
		// Ch(e,f,g) = (e & f) ^ (~e & g)
		temp1 = mod(h + k[j], 4294967296)

		// Rotate and mix
		h = g
		g = f
		f = e
		e = mod(d + temp1, 4294967296)
		d = c
		c = b
		b = a
		a = mod(temp1 + mod(b + c, 4294967296), 4294967296)
	}

	// Add compressed values to hash
	h0 = mod(h0 + a, 4294967296)
	h1 = mod(h1 + b, 4294967296)
	h2 = mod(h2 + c, 4294967296)
	h3 = mod(h3 + d, 4294967296)

	// Return 16-character hex string (first 64 bits of hash)
	return(_rs_to_hex(h0) + _rs_to_hex(h1))
}

// Convert 32-bit integer to 8-character hex string
string scalar _rs_to_hex(real scalar num)
{
	real scalar i, digit
	string scalar hex, result
	string vector hexchars

	hexchars = ("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f")
	result = ""
	num = floor(num)

	// Convert to hex (8 digits)
	for (i = 1; i <= 8; i++) {
		digit = mod(num, 16)
		result = hexchars[digit + 1] + result
		num = floor(num / 16)
	}

	return(result)
}

end
