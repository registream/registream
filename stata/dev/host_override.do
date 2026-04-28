* =============================================================================
* host_override.do — point API calls at the local dev server
* =============================================================================
*
* Overrides ONE production value: the API host, so registream/autolabel
* calls go to http://localhost:5000 instead of https://registream.org.
*
* Does NOT override the version, does NOT set any globals, and does NOT
* enable auto-approve. Any other dev behavior lives in its own sibling
* file in this directory:
*
*   auto_approve.do     — sets REGISTREAM_AUTO_APPROVE="yes" for batch tests
*   version_override.do — also overrides get_version (test 13 only)
*
* Usage:
*   do "/path/to/registream/stata/dev/host_override.do"
*
* Escape hatch: set $REGISTREAM_TEST_HOST to redirect to a different URL
* (useful for exercising error paths).
*
* Prerequisites: local Flask server running at http://localhost:5000
*   cd registream.org && flask run --host=0.0.0.0 --port=5000
* =============================================================================

capture program drop _rs_dev_utils
program define _rs_dev_utils, rclass
	version 16.0

	gettoken subcmd 0 : 0, parse(" ,")

	if ("`subcmd'" == "get_host") {
		* $REGISTREAM_TEST_HOST escape hatch lets tests point at a different
		* host (including invalid ones, to exercise error paths).
		if ("$REGISTREAM_TEST_HOST" != "") {
			return local host "$REGISTREAM_TEST_HOST"
		}
		else {
			return local host "http://localhost:5000"
		}
		exit 0
	}

	* Any other subcommand (e.g. get_version): NOT overriding.
	* Exit with a non-zero rc so the caller's `cap qui _rs_dev_utils <subcmd>`
	* check fails cleanly and the production fallback runs.
	exit 198
end
