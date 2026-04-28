* =============================================================================
* auto_approve.do — batch mode for dev + tests
* =============================================================================
*
* Sets REGISTREAM_AUTO_APPROVE="yes" so that all registream / autolabel
* interactive prompts (first-run wizard, download confirmation, integrity
* re-download, update notifications, version conflict choice) auto-return
* "yes" / choice 1 without blocking.
*
* Load this at the top of a test do-file, or in any automation script
* that must run non-interactively:
*
*   do "/path/to/registream/stata/dev/auto_approve.do"
*
* To undo (make prompts interactive again):
*   macro drop REGISTREAM_AUTO_APPROVE
* =============================================================================

global REGISTREAM_AUTO_APPROVE "yes"
