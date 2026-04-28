test_that("STATA_EPOCH points at 1960-01-01 00:00:00 UTC", {
  expect_identical(
    format(STATA_EPOCH, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    "1960-01-01 00:00:00"
  )
})


test_that("stata_clock_to_posix(0) returns the Stata epoch", {
  result <- stata_clock_to_posix(0)
  expect_equal(as.numeric(result), as.numeric(STATA_EPOCH))
})


test_that("posix_to_stata_clock(STATA_EPOCH) returns 0", {
  expect_equal(posix_to_stata_clock(STATA_EPOCH), 0)
})


test_that("round-trip preserves timestamps to millisecond precision", {
  t <- as.POSIXct("2026-04-13 12:34:56", tz = "UTC")
  ms <- posix_to_stata_clock(t)
  t2 <- stata_clock_to_posix(ms)
  expect_equal(as.numeric(t), as.numeric(t2))
})


test_that("round-trip matches a known Python-written datasets.csv value", {
  # Reference values from the real ~/.registream/autolabel/datasets.csv:
  #   dataset_key=scb_variables_eng; downloaded=2091661026000
  # That encodes 2026-03-09 xx:xx:xx UTC (approximately). The exact UTC
  # time-of-day varies with how the Python writer rounds; the test here
  # pins the round-trip stability, not the exact target string.
  ms <- 2091661026000
  t  <- stata_clock_to_posix(ms)
  expect_s3_class(t, "POSIXct")
  ms2 <- posix_to_stata_clock(t)
  expect_equal(ms, ms2)
})


test_that("NA inputs produce NA outputs without warnings", {
  expect_true(is.na(stata_clock_to_posix(NA)))
  expect_true(is.na(posix_to_stata_clock(as.POSIXct(NA, tz = "UTC"))))
})
