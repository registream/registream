test_that("compare_versions() handles the semver basics", {
  expect_true(compare_versions("3.0.0", "3.0.1"))
  expect_true(compare_versions("3.0.0", "3.1.0"))
  expect_true(compare_versions("3.0.0", "4.0.0"))
  expect_true(compare_versions("3.9.9", "4.0.0"))

  expect_false(compare_versions("3.0.0", "3.0.0"))
  expect_false(compare_versions("3.0.1", "3.0.0"))
  expect_false(compare_versions("4.0.0", "3.9.9"))
})


test_that("compare_versions() strips pre-release and build metadata", {
  expect_false(compare_versions("3.0.1-rc1", "3.0.1"))
  expect_false(compare_versions("3.0.1", "3.0.1+build.123"))
  expect_true(compare_versions("3.0.0", "3.0.1-rc1"))
})


test_that("compare_versions() treats unparseable input as no-update", {
  expect_false(compare_versions("3.0.0", "not-a-version"))
  expect_false(compare_versions("weird", "also-weird"))
})


test_that("parse_heartbeat_response() parses the key=value wire format", {
  text <- paste(
    "registream_update=true",
    "registream_latest=3.1.0",
    "autolabel_update=false",
    "autolabel_latest=",
    "datamirror_update=true",
    "datamirror_latest=1.2.3",
    sep = "\n"
  )
  result <- registream:::parse_heartbeat_response(text)
  expect_true(result$update_available)
  expect_identical(result$latest_version, "3.1.0")
  expect_false(result$autolabel_update)
  expect_identical(result$autolabel_latest, "")
  expect_true(result$datamirror_update)
  expect_identical(result$datamirror_latest, "1.2.3")
})


test_that("parse_heartbeat_response() tolerates blank lines and stray text", {
  text <- "\n\nregistream_update=false\n\nrandom_other_key=ignored\nregistream_latest=3.0.0\n"
  result <- registream:::parse_heartbeat_response(text)
  expect_false(result$update_available)
  expect_identical(result$latest_version, "3.0.0")
})


test_that("send_heartbeat() short-circuits when internet_access=FALSE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access <- FALSE
  config_save(cfg, tmp)

  result <- send_heartbeat("3.0.0", "test")
  expect_identical(result$reason, "internet_disabled")
})


test_that("send_heartbeat() returns cached result when cache is fresh", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access   <- TRUE
  cfg$auto_update_check <- TRUE
  cfg$last_update_check <- Sys.time() - 3600   # 1h ago = fresh
  cfg$update_available  <- TRUE
  cfg$latest_version    <- "3.1.0"
  config_save(cfg, tmp)

  result <- send_heartbeat("3.0.0", "test")
  expect_identical(result$reason, "cached")
  expect_true(result$update_available)
  expect_identical(result$latest_version, "3.1.0")
})


test_that("send_heartbeat() exits early when neither telemetry nor update check is on", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access   <- TRUE
  cfg$telemetry_enabled <- FALSE
  cfg$auto_update_check <- FALSE
  cfg$last_update_check <- NULL
  config_save(cfg, tmp)

  result <- send_heartbeat("3.0.0", "test")
  expect_identical(result$reason, "success")
  expect_false(result$update_available)
})


test_that("show_notification() returns empty string when no update", {
  result <- registream:::heartbeat_result()
  expect_identical(show_notification("3.0.0", result), "")
})


test_that("show_notification() formats the banner when an update is available", {
  result <- registream:::heartbeat_result(
    update_available = TRUE,
    latest_version   = "3.1.0"
  )
  banner <- show_notification("3.0.0", result)
  expect_match(banner, "A new version of registream is available", fixed = TRUE)
  expect_match(banner, "Current version:  3.0.0", fixed = TRUE)
  expect_match(banner, "Latest version:   3.1.0", fixed = TRUE)
  expect_match(banner, "rs_update()", fixed = TRUE)
})


test_that("show_notification() renders a datamirror banner when requested", {
  result <- registream:::heartbeat_result(
    datamirror_update = TRUE,
    datamirror_latest = "1.2.3"
  )
  banner <- show_notification("3.0.0", result)
  expect_match(banner, "A new version of datamirror is available", fixed = TRUE)
  expect_match(banner, "Latest version:   1.2.3", fixed = TRUE)
  expect_match(banner, "rs_update(pkg = 'datamirror')", fixed = TRUE)
})


test_that("show_notification() with modules scope suppresses siblings (policy: autolabel context)", {
  # Server reports datamirror update; autolabel-scoped call must NOT show it.
  result <- registream:::heartbeat_result(
    update_available  = TRUE,
    latest_version    = "3.1.0",
    autolabel_update  = TRUE,
    autolabel_latest  = "3.0.1",
    datamirror_update = TRUE,
    datamirror_latest = "1.2.3"
  )
  banner <- show_notification("3.0.0", result, modules = c("registream", "autolabel"))
  expect_match(banner, "A new version of registream is available", fixed = TRUE)
  expect_match(banner, "A new version of autolabel is available", fixed = TRUE)
  expect_false(grepl("datamirror", banner, fixed = TRUE))
})


test_that("show_notification() with modules scope suppresses siblings (policy: datamirror context)", {
  result <- registream:::heartbeat_result(
    update_available  = TRUE,
    latest_version    = "3.1.0",
    autolabel_update  = TRUE,
    autolabel_latest  = "3.0.1",
    datamirror_update = TRUE,
    datamirror_latest = "1.2.3"
  )
  banner <- show_notification("3.0.0", result, modules = c("registream", "datamirror"))
  expect_match(banner, "A new version of registream is available", fixed = TRUE)
  expect_match(banner, "A new version of datamirror is available", fixed = TRUE)
  expect_false(grepl("autolabel", banner, fixed = TRUE))
})


test_that("show_notification() with modules='registream' shows only core", {
  result <- registream:::heartbeat_result(
    update_available  = TRUE,
    latest_version    = "3.1.0",
    autolabel_update  = TRUE,
    autolabel_latest  = "3.0.1",
    datamirror_update = TRUE,
    datamirror_latest = "1.2.3"
  )
  banner <- show_notification("3.0.0", result, modules = "registream")
  expect_match(banner, "A new version of registream is available", fixed = TRUE)
  expect_false(grepl("autolabel",  banner, fixed = TRUE))
  expect_false(grepl("datamirror", banner, fixed = TRUE))
})


test_that("rs_update() prints the install command in non-interactive sessions", {
  out <- capture.output(result <- rs_update("cran", "registream"))
  expect_null(result)
  expect_true(any(grepl("install.packages", out, fixed = TRUE)))
  expect_true(any(grepl("cloud.r-project.org", out, fixed = TRUE)))
})


# ─── installed_version() ────────────────────────────────────────────────────

test_that("installed_version() returns NULL for missing packages", {
  expect_null(registream:::installed_version("definitely_not_a_real_pkg_xyz"))
})


test_that("installed_version() returns a version string for installed packages", {
  # `utils` is a base R package; always present.
  v <- registream:::installed_version("utils")
  expect_type(v, "character")
  expect_true(nzchar(v))
})


# ─── check_package(): module-awareness ─────────────────────────────────────

test_that("check_package() includes autolabel_version in the heartbeat URL when autolabel is installed", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access   <- TRUE
  cfg$auto_update_check <- TRUE
  cfg$last_update_check <- NULL
  config_save(cfg, tmp)

  captured <- new.env()

  testthat::local_mocked_bindings(
    installed_version = function(pkg) {
      switch(pkg, autolabel = "3.0.1", NULL)
    },
    http_get_text = function(url, timeout_seconds) {
      captured$url <- url
      "registream_update=false\nregistream_latest=\n"
    },
    .package = "registream"
  )

  check_package("3.0.0")

  expect_true(!is.null(captured$url))
  expect_match(captured$url, "autolabel=3.0.1", fixed = TRUE)
  expect_false(grepl("datamirror=", captured$url, fixed = TRUE))
  expect_match(captured$url, "registream=3.0.0", fixed = TRUE)
})


test_that("check_package() includes both modules when both are installed", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access   <- TRUE
  cfg$auto_update_check <- TRUE
  cfg$last_update_check <- NULL
  config_save(cfg, tmp)

  captured <- new.env()

  testthat::local_mocked_bindings(
    installed_version = function(pkg) {
      switch(pkg,
        autolabel  = "3.0.0",
        datamirror = "1.2.3",
        NULL
      )
    },
    http_get_text = function(url, timeout_seconds) {
      captured$url <- url
      "registream_update=false\nregistream_latest=\n"
    },
    .package = "registream"
  )

  check_package("3.0.0")

  expect_match(captured$url, "autolabel=3.0.0", fixed = TRUE)
  expect_match(captured$url, "datamirror=1.2.3", fixed = TRUE)
})


test_that("check_package() omits module params when neither is installed", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access   <- TRUE
  cfg$auto_update_check <- TRUE
  cfg$last_update_check <- NULL
  config_save(cfg, tmp)

  captured <- new.env()

  testthat::local_mocked_bindings(
    installed_version = function(pkg) NULL,
    http_get_text = function(url, timeout_seconds) {
      captured$url <- url
      "registream_update=false\nregistream_latest=\n"
    },
    .package = "registream"
  )

  check_package("3.0.0")

  expect_false(grepl("autolabel=",  captured$url, fixed = TRUE))
  expect_false(grepl("datamirror=", captured$url, fixed = TRUE))
  expect_match(captured$url, "registream=3.0.0", fixed = TRUE)
})


test_that("check_package() short-circuits to internet_disabled before calling installed_version", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$internet_access <- FALSE
  config_save(cfg, tmp)

  result <- check_package("3.0.0")
  expect_identical(result$reason, "internet_disabled")
})
