# Reusable skip helpers for CRAN + offline environments.
#
# Every network-touching test must call skip_offline_or_cran() at the top.
# CRAN runs `R CMD check` without network access, so skip_on_cran() is the
# policy-required guard; skip_if_offline() is the convenience guard for
# users running `devtools::test()` on a plane.

skip_offline_or_cran <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
}
