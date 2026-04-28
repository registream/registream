# Test helpers shared across testthat files. Auto-sourced by testthat
# before each test (helper-*.R convention).

skip_without_haven <- function() {
  testthat::skip_if_not_installed("haven")
}

skip_without_withr <- function() {
  testthat::skip_if_not_installed("withr")
}
