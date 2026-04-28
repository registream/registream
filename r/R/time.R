# Stata clock format <-> POSIXct conversion.
#
# Stata's `clock("YYYY-MM-DD HH:MM:SS", "YMDhms")` returns the number of
# milliseconds since 1960-01-01 00:00:00 UTC (the Stata epoch). Several
# RegiStream files store timestamps in this format so the Stata and
# Python clients can both read them directly:
#
#   - `datasets.csv` `downloaded` and `last_checked` columns
#   - the Stata-side `last_update_check` persisted in `config_stata.csv`
#
# R uses POSIXct throughout. These converters are the translation layer
# between the two formats. Round-trip exactness is required for
# cross-client cache compatibility: `posix_to_stata_clock(x)` followed
# by `stata_clock_to_posix(_)` must return the same POSIXct value.

STATA_EPOCH <- structure(
  -315619200,  # Unix seconds for 1960-01-01 00:00:00 UTC
  class = c("POSIXct", "POSIXt"),
  tzone = "UTC"
)

stata_clock_to_posix <- function(ms) {
  if (is.null(ms) || length(ms) == 0 || is.na(ms)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }
  as.POSIXct(as.numeric(ms) / 1000, origin = STATA_EPOCH, tz = "UTC")
}

posix_to_stata_clock <- function(t) {
  if (is.null(t) || length(t) == 0 || any(is.na(t))) {
    return(NA_real_)
  }
  unix_sec <- as.numeric(t)
  epoch_sec <- as.numeric(STATA_EPOCH)
  (unix_sec - epoch_sec) * 1000
}
