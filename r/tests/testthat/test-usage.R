test_that("compute_user_id() generates a stable 16-char hex hash", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  uid1 <- compute_user_id()
  uid2 <- compute_user_id()

  expect_identical(uid1, uid2)
  expect_identical(nchar(uid1), 16L)
  expect_match(uid1, "^[0-9a-f]+$")
})


test_that("compute_user_id() differs across distinct salt files", {
  tmp1 <- withr::local_tempdir()
  tmp2 <- withr::local_tempdir()

  withr::with_envvar(c(REGISTREAM_DIR = tmp1), uid1 <- compute_user_id())
  withr::with_envvar(c(REGISTREAM_DIR = tmp2), uid2 <- compute_user_id())

  expect_false(identical(uid1, uid2))
})


test_that("salt file is created on first compute and persists", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  salt_file <- file.path(tmp, ".salt")
  expect_false(file.exists(salt_file))

  compute_user_id()
  expect_true(file.exists(salt_file))

  salt_before <- readLines(salt_file)
  compute_user_id()  # second call should NOT regenerate
  salt_after <- readLines(salt_file)

  expect_identical(salt_before, salt_after)
  expect_identical(nchar(salt_before), 64L)
})


test_that("usage_init() creates the 9-col CSV header but no data rows", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  usage_init()
  path <- usage_path()
  expect_true(file.exists(path))

  lines <- readLines(path)
  expect_identical(length(lines), 1L)
  expect_identical(
    lines[[1]],
    "timestamp;user_id;platform;module;module_version;core_version;command_string;os;platform_version"
  )
})


test_that("usage_init() rotates a stale header to .old and starts fresh", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(tmp, "usage_r.csv")
  writeLines(
    c(
      "timestamp;user_id;platform;version;command_string;os;platform_version",
      "2025-01-01T00:00:00Z;abc;r;2.9.0;autolabel;Darwin;4.3.0"
    ),
    path
  )

  usage_init()

  old_path <- paste0(path, ".old")
  expect_true(file.exists(old_path))
  rotated <- readLines(old_path)
  expect_identical(length(rotated), 2L)
  expect_match(rotated[[1]], "^timestamp;user_id;platform;version;")

  fresh <- readLines(path)
  expect_identical(length(fresh), 1L)
  expect_match(fresh[[1]], ";module;module_version;core_version;")
})


test_that("usage_log() appends a row when usage_logging=TRUE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$usage_logging <- TRUE
  config_save(cfg, tmp)

  usage_log("autolabel", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")
  usage_log("rs_lookup kon", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")
  usage_log("rs_update", module = "registream",
            module_version = "3.0.0", core_version = "3.0.0")

  lines <- readLines(usage_path())
  expect_identical(length(lines), 4L)  # header + 3 rows
  expect_match(lines[[2]], ";r;autolabel;3\\.0\\.0;3\\.0\\.0;autolabel;")
  expect_match(lines[[3]], ";r;autolabel;3\\.0\\.0;3\\.0\\.0;rs_lookup kon;")
  expect_match(lines[[4]], ";r;registream;3\\.0\\.0;3\\.0\\.0;rs_update;")
})


test_that("usage_log() is a silent no-op when usage_logging=FALSE", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$usage_logging <- FALSE
  config_save(cfg, tmp)

  usage_log("autolabel", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")
  expect_false(file.exists(usage_path()))
})


test_that("rs_stats() returns empty stats when the log doesn't exist", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  result <- rs_stats()
  expect_s3_class(result, "registream_usage_stats")
  expect_identical(result$total_calls, 0L)
  expect_identical(result$unique_users, 0L)
  expect_true(is.na(result$first_use))
  expect_true(is.na(result$last_use))
})


test_that("rs_stats() aggregates rows for the current user", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$usage_logging <- TRUE
  config_save(cfg, tmp)

  usage_log("autolabel", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")
  Sys.sleep(0.01)
  usage_log("rs_lookup", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")
  usage_log("autolabel_scope", module = "autolabel",
            module_version = "3.0.0", core_version = "3.0.0")

  result <- rs_stats()
  expect_identical(result$total_calls, 3L)
  expect_identical(result$unique_users, 1L)
  expect_s3_class(result$first_use, "POSIXt")
  expect_s3_class(result$last_use, "POSIXt")
})


test_that("rs_stats(all_users = TRUE) counts across user_ids", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$usage_logging <- TRUE
  config_save(cfg, tmp)

  usage_init()
  # Inject two rows with different user_ids directly (9-col schema)
  path <- usage_path()
  cat(
    "2026-04-13T10:00:00Z;abc123;r;autolabel;3.0.0;3.0.0;autolabel;Darwin;4.3.0\n",
    "2026-04-13T10:01:00Z;def456;r;autolabel;3.0.0;3.0.0;autolabel;Linux;4.3.1\n",
    file = path, append = TRUE, sep = ""
  )

  all_stats <- rs_stats(all_users = TRUE)
  expect_identical(all_stats$unique_users, 2L)
  # all_users=TRUE does NOT filter; both injected rows count
  expect_identical(all_stats$total_calls, 2L)

  # The default (all_users=FALSE) DOES filter out the injected rows because
  # their user_ids don't match the current-process user_id.
  user_stats <- rs_stats(all_users = FALSE)
  expect_identical(user_stats$total_calls, 0L)
  expect_identical(user_stats$unique_users, 2L)  # unique counted pre-filter
})
