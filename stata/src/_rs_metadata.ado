* =============================================================================
* RegiStream Metadata Registry
* Shared datasets.csv management for all modules.
* Provides read, write, and integrity checking for cached metadata files.
* =============================================================================
program define _rs_metadata, rclass
	version 16.0
	gettoken subcmd 0 : 0

	if ("`subcmd'" == "get_version") {
		_meta_get_version `0'
		return add
	}
	else if ("`subcmd'" == "store") {
		_meta_store `0'
	}
	else if ("`subcmd'" == "check_integrity") {
		_meta_check_integrity `0'
		return add
	}
	else {
		di as error "Invalid _rs_metadata subcommand: `subcmd'"
		exit 198
	}
end

* -----------------------------------------------------------------------------
* get_version: Retrieve stored version info for a dataset from datasets.csv
* Args: cache_dir domain type lang
* Returns: r(has_version), r(version), r(schema), r(downloaded), r(source),
*          r(file_size_dta), r(file_size_csv), r(last_checked)
* -----------------------------------------------------------------------------
program define _meta_get_version, rclass
	args cache_dir domain type lang

	* Create dataset key (convert "values" → "value_labels" for the key)
	local file_type = cond("`type'" == "values", "value_labels", "`type'")
	local dataset_key "`domain'_`file_type'_`lang'"
	local meta_csv "`cache_dir'/datasets.csv"

	* Check if registry exists
	cap confirm file "`meta_csv'"
	if (_rc != 0) {
		return scalar has_version = 0
		return local version ""
		return local schema ""
		return local downloaded ""
		return local file_size_dta ""
		return local file_size_csv ""
		return local last_checked ""
		exit 0
	}

	* Read CSV (preserve/restore to avoid corrupting user's dataset)
	quietly {
		preserve
		cap import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
		if (_rc == 0) {
			cap keep if dataset_key == "`dataset_key'"
			if (_rc == 0 & _N > 0) {
				local ver `=version[1]'
				local sch `=schema[1]'
				local dl `=downloaded[1]'
				local src `=source[1]'
				* file_size_dta (new) with fallback to file_size (legacy)
				cap local fs_dta `=file_size_dta[1]'
				if (_rc != 0 | "`fs_dta'" == "" | "`fs_dta'" == ".") {
					cap local fs_dta `=file_size[1]'
				}
				if (_rc != 0) local fs_dta ""
				* file_size_csv
				cap local fs_csv `=file_size_csv[1]'
				if (_rc != 0 | "`fs_csv'" == "" | "`fs_csv'" == ".") local fs_csv ""
				* last_checked
				cap local lc `=last_checked[1]'
				if (_rc != 0) local lc ""

				return scalar has_version = 1
				return local version "`ver'"
				return local schema "`sch'"
				return local downloaded "`dl'"
				return local source "`src'"
				return local file_size_dta "`fs_dta'"
				return local file_size_csv "`fs_csv'"
				return local last_checked "`lc'"
				restore
				exit 0
			}
			else {
				restore
				return scalar has_version = 0
				return local version ""
				return local schema ""
				return local downloaded ""
				return local file_size_dta ""
				return local file_size_csv ""
				return local last_checked ""
				exit 0
			}
		}
		else {
			restore
			return scalar has_version = 0
			return local version ""
			return local schema ""
			return local downloaded ""
			return local file_size_dta ""
			return local file_size_csv ""
			return local last_checked ""
			exit 0
		}
	}
end

* -----------------------------------------------------------------------------
* store: Write or update a dataset entry in datasets.csv
* Args: cache_dir domain type lang ds_version ds_schema dta_file
* The CSV and DTA file sizes are computed automatically from dta_file path.
* -----------------------------------------------------------------------------
program define _meta_store
	args cache_dir domain type lang ds_version ds_schema dta_file

	local file_type = cond("`type'" == "values", "value_labels", "`type'")
	local dataset_key "`domain'_`file_type'_`lang'"
	local timestamp = clock("`c(current_date)' `c(current_time)'", "DMY hms")

	* Get DTA file size
	local file_size_dta = 0
	cap confirm file "`dta_file'"
	if (_rc == 0) {
		_rs_utils get_filesize "`dta_file'"
		local file_size_dta = r(size)
	}
	if ("`file_size_dta'" == "" | "`file_size_dta'" == ".") local file_size_dta = 0

	* Get CSV file size (derive path from DTA path)
	local csv_file = subinstr("`dta_file'", ".dta", ".csv", 1)
	local file_size_csv = 0
	cap confirm file "`csv_file'"
	if (_rc == 0) {
		_rs_utils get_filesize "`csv_file'"
		local file_size_csv = r(size)
	}
	if ("`file_size_csv'" == "" | "`file_size_csv'" == ".") local file_size_csv = 0

	local meta_csv "`cache_dir'/datasets.csv"

	* Check if registry exists
	cap confirm file "`meta_csv'"
	if (_rc != 0) {
		* Create new CSV with header
		cap file close metafile
		quietly file open metafile using "`meta_csv'", write replace
		file write metafile "dataset_key;domain;type;lang;version;schema;downloaded;source;file_size_dta;file_size_csv;last_checked" _n
		file write metafile "`dataset_key';`domain';`type';`lang';`ds_version';`ds_schema';`timestamp';api;`file_size_dta';`file_size_csv';`timestamp'" _n
		file close metafile
	}
	else {
		* Check if dataset_key already exists
		quietly {
			preserve
			import delimited using "`meta_csv'", clear varnames(1) stringcols(_all) delimiter(";")
			count if dataset_key == "`dataset_key'"
			local key_exists = r(N)

			if (`key_exists' > 0) {
				* Update existing entry
				replace domain = "`domain'" if dataset_key == "`dataset_key'"
				replace type = "`type'" if dataset_key == "`dataset_key'"
				replace lang = "`lang'" if dataset_key == "`dataset_key'"
				replace version = "`ds_version'" if dataset_key == "`dataset_key'"
				replace schema = "`ds_schema'" if dataset_key == "`dataset_key'"
				replace downloaded = "`timestamp'" if dataset_key == "`dataset_key'"
				replace source = "api" if dataset_key == "`dataset_key'"
				cap confirm variable file_size_dta
				if (_rc == 0) {
					replace file_size_dta = "`file_size_dta'" if dataset_key == "`dataset_key'"
					replace file_size_csv = "`file_size_csv'" if dataset_key == "`dataset_key'"
				}
				else {
					cap confirm variable file_size
					if (_rc == 0) replace file_size = "`file_size_dta'" if dataset_key == "`dataset_key'"
				}
				export delimited using "`meta_csv'", replace delimiter(";")
			}
			else {
				restore
				cap file close metafile
				file open metafile using "`meta_csv'", write append
				file write metafile "`dataset_key';`domain';`type';`lang';`ds_version';`ds_schema';`timestamp';api;`file_size_dta';`file_size_csv';`timestamp'" _n
				file close metafile
				exit 0
			}
			restore
		}
	}
end

* -----------------------------------------------------------------------------
* check_integrity: Compare actual file sizes against stored values
* Args: cache_dir domain type lang dta_file csv_file
* Returns: r(dta_ok), r(csv_ok), r(stored_dta), r(actual_dta), r(stored_csv), r(actual_csv)
* Pure check: no prompting, no downloading. Caller decides what to do.
* -----------------------------------------------------------------------------
program define _meta_check_integrity, rclass
	args cache_dir domain type lang dta_file csv_file

	return scalar dta_ok = 1
	return scalar csv_ok = 1
	return local stored_dta ""
	return local actual_dta ""
	return local stored_csv ""
	return local actual_csv ""

	* Get stored metadata
	_rs_metadata get_version "`cache_dir'" "`domain'" "`type'" "`lang'"
	if (r(has_version) == 0) {
		* No registry entry; can't check
		exit 0
	}
	local stored_dta "`r(file_size_dta)'"
	local stored_csv "`r(file_size_csv)'"

	* Check DTA
	if ("`stored_dta'" != "" & "`stored_dta'" != "0") {
		cap confirm file "`dta_file'"
		if (_rc == 0) {
			_rs_utils get_filesize "`dta_file'"
			local actual_dta = r(size)
			if ("`actual_dta'" == "" | "`actual_dta'" == ".") local actual_dta = 0

			if (`actual_dta' != `stored_dta') {
				return scalar dta_ok = 0
			}
			return local stored_dta "`stored_dta'"
			return local actual_dta "`actual_dta'"
		}
	}

	* Check CSV
	if ("`stored_csv'" != "" & "`stored_csv'" != "0") {
		cap confirm file "`csv_file'"
		if (_rc == 0) {
			_rs_utils get_filesize "`csv_file'"
			local actual_csv = r(size)
			if ("`actual_csv'" == "" | "`actual_csv'" == ".") local actual_csv = 0

			if (`actual_csv' != `stored_csv') {
				return scalar csv_ok = 0
			}
			return local stored_csv "`stored_csv'"
			return local actual_csv "`actual_csv'"
		}
	}
end
