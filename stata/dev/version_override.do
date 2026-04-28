* =============================================================================
* version_override.do — dev override that includes get_version
* =============================================================================
*
* A strict superset of host_override.do: overrides both the API
* host AND the version string. Load this when a test needs the version
* override path (test 13_version_resolution_priority is the primary user).
*
* Both overrides have $REGISTREAM_TEST_* escape hatches:
*   $REGISTREAM_TEST_HOST    — override the returned host URL
*   $REGISTREAM_TEST_VERSION — override the returned version string
*
* Defaults when no global is set:
*   host    -> http://localhost:5000
*   version -> 2.0.0
*
* Usage:
*   do "/path/to/registream/stata/dev/version_override.do"
*
* Because each `do` of this file completely redefines _rs_dev_utils, a
* subsequent `do` of host_override.do (which only handles
* get_host) will REVERT the version override. Pick one or the other.
* =============================================================================

capture program drop _rs_dev_utils
program define _rs_dev_utils, rclass
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "get_host") {
		if ("$REGISTREAM_TEST_HOST" != "") {
			return local host "$REGISTREAM_TEST_HOST"
		}
		else {
			return local host "http://localhost:5000"
		}
		exit 0
	}
	else if ("`subcmd'" == "get_version") {
		if ("$REGISTREAM_TEST_VERSION" != "") {
			return local version "$REGISTREAM_TEST_VERSION"
		}
		else {
			return local version "2.0.0"
		}
		exit 0
	}

	* Unknown subcommand — fall through to production
	exit 198
end
