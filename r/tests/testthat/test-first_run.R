test_that("config_for_choice() maps the three modes exactly like Python", {
  offline <- registream:::config_for_choice("1")
  expect_true(offline$usage_logging)
  expect_false(offline$telemetry_enabled)
  expect_false(offline$internet_access)
  expect_false(offline$auto_update_check)
  expect_true(offline$first_run_completed)

  standard <- registream:::config_for_choice("2")
  expect_true(standard$usage_logging)
  expect_false(standard$telemetry_enabled)
  expect_true(standard$internet_access)
  expect_true(standard$auto_update_check)
  expect_true(standard$first_run_completed)

  full <- registream:::config_for_choice("3")
  expect_true(full$usage_logging)
  expect_true(full$telemetry_enabled)
  expect_true(full$internet_access)
  expect_true(full$auto_update_check)
  expect_true(full$first_run_completed)
})


test_that("config_for_choice() rejects unknown choices", {
  expect_error(registream:::config_for_choice("4"), "Invalid choice")
  expect_error(registream:::config_for_choice(""),  "Invalid choice")
})


test_that("rs_first_run(): REGISTREAM_AUTO_APPROVE=yes silently picks Full Mode + isolated cache", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_AUTO_APPROVE = "yes")

  cfg <- rs_first_run(directory = tmp)
  expect_true(cfg$first_run_completed)
  expect_true(cfg$telemetry_enabled)       # Full Mode has telemetry ON
  expect_true(cfg$internet_access)
  expect_true(file.exists(file.path(tmp, "config_r.toml")))
  # CRAN-safe: AUTO_APPROVE must NOT silently opt into ~/.registream/
  expect_false(nzchar(cfg$cache_dir))
})


test_that("rs_first_run(): non-interactive session with no AUTO_APPROVE writes transient Offline Mode + isolated cache + first_run_completed=FALSE", {
  # testthat already runs in a non-interactive session, so this path exercises
  # the CRAN-safe default without needing to mock interactive().
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_AUTO_APPROVE = NA)  # unset

  cfg <- rs_first_run(directory = tmp)
  # first_run_completed MUST stay FALSE so the next interactive session
  # re-fires the wizard. Locking users into Offline via a silent Rscript
  # fallback is the specific bug this guards against.
  expect_false(cfg$first_run_completed)
  expect_false(cfg$telemetry_enabled)
  expect_false(cfg$internet_access)         # Offline Mode: no network
  expect_false(cfg$auto_update_check)
  # CRAN-compliance guard: a non-interactive first run MUST leave cache_dir
  # empty so that cache_dir() falls back to tools::R_user_dir(). The shared
  # ~/.registream/ path is only reachable via the interactive Y/N prompt.
  expect_false(nzchar(cfg$cache_dir))
})


test_that("rs_first_run(): non-interactive run is re-enterable; no lock-in", {
  # A non-interactive Rscript/CI run must not commit the user to Offline
  # Mode permanently. After the first call leaves first_run_completed=FALSE
  # on disk, a second call in the same conditions must re-enter the
  # decision logic (not short-circuit via the first_run_completed branch).
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_AUTO_APPROVE = NA)

  cfg1 <- rs_first_run(directory = tmp)
  expect_false(cfg1$first_run_completed)

  cfg2 <- rs_first_run(directory = tmp)
  expect_false(cfg2$first_run_completed)
  # Both calls produced the same transient Offline shape; not a short
  # circuit via the "already completed, return existing" branch.
  expect_identical(cfg1$telemetry_enabled, cfg2$telemetry_enabled)
  expect_identical(cfg1$internet_access,   cfg2$internet_access)
})


test_that("rs_first_run(): skipped if first_run_completed unless force=TRUE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_AUTO_APPROVE = "yes")

  cfg1 <- rs_first_run(directory = tmp)
  expect_true(cfg1$telemetry_enabled)  # Full Mode

  # Write a marker that would be overwritten if save() ran again
  config_set("telemetry_enabled", FALSE, tmp)

  cfg2 <- rs_first_run(directory = tmp)
  expect_false(cfg2$telemetry_enabled)  # short-circuit: no re-save

  cfg3 <- rs_first_run(directory = tmp, force = TRUE)
  expect_true(cfg3$telemetry_enabled)   # forced re-run: back to Full Mode
})
