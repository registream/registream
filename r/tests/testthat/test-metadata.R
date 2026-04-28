# Metadata loader tests: load_metadata, cache_filename, bundle_path,
# autolabel_cache_path. v3-only (load_registers + detect_schema_version
# were retired with the rest of the v1/v2 surface).

load_metadata        <- getFromNamespace("load_metadata",        "registream")
cache_filename       <- getFromNamespace("cache_filename",       "registream")
autolabel_cache_path <- getFromNamespace("autolabel_cache_path", "registream")
bundle_path          <- getFromNamespace("bundle_path",          "registream")


# ── cache_filename ───────────────────────────────────────────────────────────

test_that("cache_filename builds expected names", {
  expect_equal(cache_filename("scb", "variables", "eng"),
               "scb_variables_eng.dta")
  expect_equal(cache_filename("scb", "values",    "eng"),
               "scb_value_labels_eng.dta")
  expect_equal(cache_filename("scb", "values",    "eng", ext = "csv"),
               "scb_value_labels_eng.csv")
  expect_equal(cache_filename("scb", "scope",     "eng"),
               "scb_scope_eng.dta")
})

test_that("cache_filename rejects unknown file_type", {
  expect_error(cache_filename("scb", "bogus", "eng"),
               regexp = "Invalid file_type")
})


# ── bundle_path uses per-domain layout ───────────────────────────────────────

test_that("bundle_path nests under <cache>/autolabel/<domain>/", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  p <- bundle_path("scb", "variables", "eng")
  expect_match(normalizePath(dirname(p), winslash = "/", mustWork = FALSE),
               "autolabel/scb$")
  expect_identical(basename(p), "variables_eng.dta")
})


# ── load_metadata: end-to-end against a v3 bundle file ───────────────────────

test_that("load_metadata reads variables from the v3 per-domain layout", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  haven::write_dta(
    data.frame(
      variable_name  = c("age", "sex"),
      variable_label = c("Age", "Sex"),
      variable_type  = c("continuous", "categorical"),
      release_set_id = c(1L, 1L),
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )

  df <- load_metadata("scb", "variables", "eng")
  expect_s3_class(df, "data.frame")
  expect_setequal(as.character(df$variable_name), c("age", "sex"))
})


test_that("load_metadata raises FileNotFound when the file is missing", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)
  expect_error(load_metadata("scb", "variables", "eng"),
               regexp = "No cached metadata found")
})


test_that("load_metadata accepts an explicit directory override", {
  skip_without_withr()
  tmp <- withr::local_tempdir()
  d <- file.path(tmp, "autolabel", "scb")
  dir.create(d, recursive = TRUE)
  haven::write_dta(
    data.frame(
      variable_name  = "age",
      variable_label = "Age",
      variable_type  = "continuous",
      release_set_id = 1L,
      stringsAsFactors = FALSE
    ),
    file.path(d, "variables_eng.dta")
  )

  df <- load_metadata("scb", "variables", "eng", directory = tmp)
  expect_identical(as.character(df$variable_name), "age")
})
