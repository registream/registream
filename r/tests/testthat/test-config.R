test_that("config_defaults() returns the typed record with Python-matching fields", {
  cfg <- config_defaults()
  expect_s3_class(cfg, "registream_config")
  expected_keys <- c(
    "usage_logging", "telemetry_enabled", "internet_access",
    "auto_update_check", "last_update_check", "update_available",
    "latest_version",
    "autolabel_update_available", "autolabel_latest_version",
    "datamirror_update_available", "datamirror_latest_version",
    "first_run_completed", "cache_dir"
  )
  expect_identical(names(cfg), expected_keys)
  expect_true(cfg$usage_logging)
  expect_true(cfg$telemetry_enabled)
  expect_true(cfg$internet_access)
  expect_true(cfg$auto_update_check)
  expect_false(cfg$first_run_completed)
  expect_false(cfg$autolabel_update_available)
  expect_false(cfg$datamirror_update_available)
  expect_identical(cfg$autolabel_latest_version, "")
  expect_identical(cfg$datamirror_latest_version, "")
  expect_null(cfg$last_update_check)
  expect_identical(cfg$cache_dir, "")
})


test_that("config_load() on a missing file returns defaults without writing", {
  tmp <- withr::local_tempdir()
  cfg <- config_load(tmp)
  expect_s3_class(cfg, "registream_config")
  expect_false(file.exists(file.path(tmp, "config_r.toml")))
  expect_identical(cfg, config_defaults())
})


test_that("config_init() creates a default config file if missing, else loads", {
  tmp <- withr::local_tempdir()
  cfg1 <- config_init(tmp)
  expect_true(file.exists(file.path(tmp, "config_r.toml")))
  cfg2 <- config_init(tmp)
  expect_identical(
    cfg1[names(cfg1) != "last_update_check"],
    cfg2[names(cfg2) != "last_update_check"]
  )
})


test_that("config_save() + config_load() round-trip all field types", {
  tmp <- withr::local_tempdir()
  cfg <- config_defaults()
  cfg$usage_logging       <- FALSE
  cfg$telemetry_enabled   <- FALSE
  cfg$internet_access     <- TRUE
  cfg$auto_update_check   <- FALSE
  cfg$latest_version      <- "3.1.0"
  cfg$first_run_completed <- TRUE
  cfg$cache_dir           <- "/tmp/shared_cache"

  config_save(cfg, tmp)
  loaded <- config_load(tmp)

  expect_false(loaded$usage_logging)
  expect_false(loaded$telemetry_enabled)
  expect_true(loaded$internet_access)
  expect_false(loaded$auto_update_check)
  expect_identical(loaded$latest_version, "3.1.0")
  expect_true(loaded$first_run_completed)
  expect_identical(loaded$cache_dir, "/tmp/shared_cache")
})


test_that("config_load() ignores unknown keys (forward compatibility)", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "config_r.toml")
  writeLines(
    c(
      'usage_logging = false',
      'future_field_from_v4 = "unknown"',
      'another_unknown = 42'
    ),
    path
  )
  cfg <- config_load(tmp)
  expect_false(cfg$usage_logging)
  expect_identical(names(cfg), names(config_defaults()))
})


test_that("config_get() and config_set() read/write single fields", {
  tmp <- withr::local_tempdir()
  config_save(config_defaults(), tmp)

  expect_true(config_get("telemetry_enabled", tmp))
  config_set("telemetry_enabled", FALSE, tmp)
  expect_false(config_get("telemetry_enabled", tmp))

  expect_error(config_get("not_a_real_key", tmp), "Unknown config key")
  expect_error(config_set("not_a_real_key", "x", tmp), "Unknown config key")
})


test_that("TOML writer quotes strings and escapes special characters", {
  tmp <- withr::local_tempdir()
  cfg <- config_defaults()
  cfg$latest_version <- 'weird "quoted" string with \\ backslash'
  config_save(cfg, tmp)

  loaded <- config_load(tmp)
  expect_identical(loaded$latest_version, cfg$latest_version)
})


test_that("TOML reader treats # as a comment outside quoted strings", {
  tmp <- withr::local_tempdir()
  path <- file.path(tmp, "config_r.toml")
  writeLines(
    c(
      '# full-line comment',
      'usage_logging = true  # trailing comment',
      'latest_version = "3.0.0 # not a comment inside quotes"',
      '',
      'telemetry_enabled = false'
    ),
    path
  )
  cfg <- config_load(tmp)
  expect_true(cfg$usage_logging)
  expect_false(cfg$telemetry_enabled)
  expect_identical(cfg$latest_version, "3.0.0 # not a comment inside quotes")
})


test_that("last_update_check round-trips as ISO 8601 UTC", {
  tmp <- withr::local_tempdir()
  cfg <- config_defaults()
  cfg$last_update_check <- as.POSIXct("2026-04-13 12:34:56", tz = "UTC")
  config_save(cfg, tmp)

  loaded <- config_load(tmp)
  expect_s3_class(loaded$last_update_check, "POSIXt")
  expect_equal(
    as.numeric(loaded$last_update_check),
    as.numeric(cfg$last_update_check)
  )
})
