# POST batch heartbeat: JSON payload construction + pending-row read.

test_that("read_pending_usage() returns empty when file absent", {
  tmp <- withr::local_tempdir()
  expect_identical(nrow(read_pending_usage(tmp)), 0L)
})


test_that("read_pending_usage() filters on since timestamp", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  cfg <- config_defaults()
  cfg$usage_logging <- TRUE
  config_save(cfg, tmp)

  usage_init()
  path <- usage_path()
  # Write three rows with known timestamps
  cat(
    "2026-04-10T00:00:00Z;u1;r;autolabel;3.0.0;3.0.0;old1;Darwin;4.3.0\n",
    "2026-04-15T00:00:00Z;u1;r;autolabel;3.0.0;3.0.0;old2;Darwin;4.3.0\n",
    "2026-04-20T00:00:00Z;u1;r;autolabel;3.0.0;3.0.0;recent;Darwin;4.3.0\n",
    file = path, append = TRUE, sep = ""
  )

  since <- as.POSIXct("2026-04-12T00:00:00Z", tz = "UTC")
  pending <- read_pending_usage(tmp, since = since)
  expect_identical(nrow(pending), 2L)
  expect_setequal(pending$command_string, c("old2", "recent"))
})


test_that("build_heartbeat_payload() emits Python-compatible JSON shape", {
  pending <- data.frame(
    timestamp       = c("2026-04-20T00:00:00Z", "2026-04-21T00:00:00Z"),
    user_id         = c("u1", "u1"),
    platform        = c("r", "r"),
    module          = c("autolabel", "registream"),
    module_version  = c("3.0.0", "3.0.0"),
    core_version    = c("3.0.0", "3.0.0"),
    command_string  = c("autolabel", "rs_update"),
    os              = c("Darwin", "Darwin"),
    platform_version = c("4.3.0", "4.3.0"),
    stringsAsFactors = FALSE
  )

  json <- build_heartbeat_payload("3.0.0", pending)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)

  expect_identical(parsed$format, "stata")
  expect_identical(parsed$registream, "3.0.0")
  expect_identical(length(parsed$usage), 2L)
  expect_identical(parsed$usage[[1]]$command_string, "autolabel")
  expect_identical(parsed$usage[[1]]$module, "autolabel")
  expect_identical(parsed$usage[[2]]$module, "registream")
})
