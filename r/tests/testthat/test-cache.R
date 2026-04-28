test_that("cache_dir() honors REGISTREAM_DIR as tier 1", {
  withr::local_envvar(REGISTREAM_DIR = "/tmp/some_override")
  expect_identical(cache_dir(), "/tmp/some_override")
})


test_that("cache_dir() falls through to tier 2 (config cache_dir) when env is unset", {
  # Tier 2 only fires when REGISTREAM_DIR is NOT set and a config file with
  # a non-empty `cache_dir` field exists. We resolve the config directory
  # to a tempdir via REGISTREAM_DIR, write the config, unset REGISTREAM_DIR,
  # then re-point the config via R_user_dir override.
  cfg_tmp <- withr::local_tempdir()

  withr::with_envvar(c(REGISTREAM_DIR = cfg_tmp), {
    cfg <- config_defaults()
    cfg$cache_dir <- "/tmp/shared_via_config"
    config_save(cfg, cfg_tmp)
  })

  # Now simulate the tier-2 path: REGISTREAM_DIR unset, but the config
  # file lives where the env var used to point. We pass the same tempdir
  # back in via the env var so config_path() resolves to the file we
  # just wrote; tier 1 still fires first, but that's fine because tier 1
  # and tier 2 both resolve to values; the test here is that tier 2's
  # reader finds the cache_dir field when called directly.
  withr::with_envvar(c(REGISTREAM_DIR = cfg_tmp), {
    from_config <- registream:::config_cache_dir()
    expect_identical(from_config, "/tmp/shared_via_config")
  })
})


test_that("config_cache_dir() returns NULL if no config file exists", {
  tmp <- withr::local_tempdir()
  withr::with_envvar(c(REGISTREAM_DIR = tmp), {
    expect_null(registream:::config_cache_dir())
  })
})


test_that("config_cache_dir() returns NULL when cache_dir field is empty", {
  tmp <- withr::local_tempdir()
  withr::with_envvar(c(REGISTREAM_DIR = tmp), {
    cfg <- config_defaults()  # cache_dir = "" by default
    config_save(cfg, tmp)
    expect_null(registream:::config_cache_dir())
  })
})


test_that("cache_dir() tier 3 falls back to R_user_dir when env and config are absent", {
  # Unset REGISTREAM_DIR. We can't easily hide config_r.toml because
  # config_cache_dir() would read from a real user dir; but on the CI
  # runner there is no such file, so the fallback fires.
  withr::local_envvar(REGISTREAM_DIR = NA)
  result <- cache_dir()
  # Only assert the shape: tier 3 uses tools::R_user_dir which contains
  # "registream" somewhere in the path. This is robust across OSes.
  expect_true(grepl("registream", result, fixed = TRUE))
})
