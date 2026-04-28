test_that("info_lines() renders the Directory, Config file, version, and settings", {
  tmp <- withr::local_tempdir()
  cfg <- config_defaults()
  cfg$usage_logging     <- TRUE
  cfg$telemetry_enabled <- FALSE
  cfg$internet_access   <- TRUE
  cfg$auto_update_check <- TRUE
  config_save(cfg, tmp)

  lines <- registream:::info_lines(directory = tmp)
  text <- paste(lines, collapse = "\n")

  expect_match(text, "RegiStream Configuration", fixed = TRUE)
  expect_match(text, "Directory:", fixed = TRUE)
  expect_match(text, "Config file:", fixed = TRUE)
  expect_match(text, "Package:", fixed = TRUE)
  expect_match(text, "Settings:", fixed = TRUE)
  expect_match(text, "usage_logging:       true", fixed = TRUE)
  expect_match(text, "telemetry_enabled:   false", fixed = TRUE)
  expect_match(text, "internet_access:     true", fixed = TRUE)
  expect_match(text, "auto_update_check:   true", fixed = TRUE)
  expect_match(text, "Citation:", fixed = TRUE)
})


test_that("rs_info() prints and returns invisibly", {
  tmp <- withr::local_tempdir()
  config_save(config_defaults(), tmp)

  out <- capture.output(result <- rs_info(directory = tmp))
  expect_true(length(out) > 10)
  expect_true(any(grepl("RegiStream Configuration", out, fixed = TRUE)))
  expect_identical(result, registream:::info_lines(directory = tmp))
})
