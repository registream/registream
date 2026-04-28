# Bundle loader tests: v3 5-file bundle (manifest + variables +
# value_labels + scope + release_sets), per-domain layout.
#
# Fixtures are built inline (no external test data) so the test tree
# stays CRAN-friendly. Each test writes a canonical synthetic bundle
# into a tmpdir and exercises one loader path.

write_manifest_csv <- function(dir, domain, lang, scope_depth = 2L,
                               schema_version = "2.0",
                               extra_kv = list()) {
  rows <- c(
    c("domain",              domain),
    c("schema_version",      schema_version),
    c("publisher",           "SCB"),
    c("bundle_release_date", "2026-04-17"),
    c("languages",           "eng|swe"),
    c("scope_depth",         as.character(scope_depth))
  )
  for (i in seq_len(scope_depth)) {
    rows <- c(rows,
              sprintf("scope_level_%d_name", i),
              sprintf("level%d", i),
              sprintf("scope_level_%d_title", i),
              sprintf("Level %d title", i))
  }
  for (k in names(extra_kv)) {
    rows <- c(rows, k, as.character(extra_kv[[k]]))
  }
  mat <- matrix(rows, ncol = 2L, byrow = TRUE)
  df <- data.frame(key = mat[, 1L], value = mat[, 2L],
                   stringsAsFactors = FALSE)
  path <- file.path(dir, sprintf("manifest_%s.csv", lang))
  utils::write.table(df, path, sep = ";", row.names = FALSE,
                     col.names = TRUE, quote = FALSE, fileEncoding = "UTF-8")
  path
}


write_bundle_files <- function(dir, lang, scope_depth = 2L) {
  vars <- data.frame(
    variable_name  = c("age", "sex"),
    variable_label = c("Age in years", "Sex"),
    variable_type  = c("continuous", "categorical"),
    release_set_id = c(1L, 1L),
    stringsAsFactors = FALSE
  )
  vlabs <- data.frame(
    value_label_id     = "sex_lbl",
    value_labels_json  = '{"1":"Man","2":"Woman"}',
    value_labels_stata = "1 Man 2 Woman",
    code_count         = 2L,
    stringsAsFactors = FALSE
  )
  scope_cols <- list(
    scope_id      = c(1L, 2L),
    scope_level_1 = c("LISA", "BR"),
    release       = c("2021", "2021")
  )
  if (scope_depth >= 2L) {
    scope_cols$scope_level_2 <- c("Individer", "Barn")
  }
  scope_df <- as.data.frame(scope_cols, stringsAsFactors = FALSE)
  rset <- data.frame(
    release_set_id = c(1L, 1L),
    scope_id       = c(1L, 2L),
    stringsAsFactors = FALSE
  )

  utils::write.table(vars,
                     file.path(dir, sprintf("variables_%s.csv", lang)),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")
  utils::write.table(vlabs,
                     file.path(dir, sprintf("value_labels_%s.csv", lang)),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")
  utils::write.table(scope_df,
                     file.path(dir, sprintf("scope_%s.csv", lang)),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")
  utils::write.table(rset,
                     file.path(dir, sprintf("release_sets_%s.csv", lang)),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")
}


test_that("validate_manifest() parses a well-formed manifest", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "autolabel", "scb"), recursive = TRUE)
  write_manifest_csv(file.path(tmp, "autolabel", "scb"), "scb", "eng",
                     scope_depth = 2L)

  m <- validate_manifest(read_metadata_csv(
    file.path(tmp, "autolabel", "scb", "manifest_eng.csv")
  ))

  expect_s3_class(m, "rs_manifest")
  expect_identical(m$domain, "scb")
  expect_identical(m$schema_version, "2.0")
  expect_identical(m$publisher, "SCB")
  expect_identical(m$languages, c("eng", "swe"))
  expect_identical(m$scope_depth, 2L)
  expect_identical(m$level_names, c("level1", "level2"))
  expect_identical(m$level_titles, c("Level 1 title", "Level 2 title"))
})


test_that("validate_manifest() rejects wrong schema_version", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "autolabel", "scb"), recursive = TRUE)
  write_manifest_csv(file.path(tmp, "autolabel", "scb"), "scb", "eng",
                     schema_version = "1.0")

  path <- file.path(tmp, "autolabel", "scb", "manifest_eng.csv")
  expect_error(
    validate_manifest(read_metadata_csv(path)),
    class = "rs_error_schema"
  )
})


test_that("validate_manifest() rejects missing scope_level_N_name", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "autolabel", "scb"), recursive = TRUE)
  # Write a manifest with scope_depth=3 but only names for levels 1..2
  rows <- c(
    "domain", "scb",
    "schema_version", "2.0",
    "publisher", "SCB",
    "bundle_release_date", "2026-04-17",
    "languages", "eng",
    "scope_depth", "3",
    "scope_level_1_name", "level1",
    "scope_level_1_title", "Level 1",
    "scope_level_2_name", "level2",
    "scope_level_2_title", "Level 2"
  )
  mat <- matrix(rows, ncol = 2L, byrow = TRUE)
  df <- data.frame(key = mat[, 1L], value = mat[, 2L],
                   stringsAsFactors = FALSE)
  path <- file.path(tmp, "autolabel", "scb", "manifest_eng.csv")
  utils::write.table(df, path, sep = ";", row.names = FALSE,
                     col.names = TRUE, quote = FALSE, fileEncoding = "UTF-8")

  expect_error(
    validate_manifest(read_metadata_csv(path)),
    class = "rs_error_schema"
  )
})


test_that("synth_core_only_manifest() returns a valid rs_manifest", {
  m <- synth_core_only_manifest("scb", "eng")
  expect_s3_class(m, "rs_manifest")
  expect_identical(m$scope_depth, 0L)
  expect_identical(m$languages, "eng")
  expect_identical(m$level_names, character(0))
})


test_that("validate_scope() checks depth matches manifest", {
  df <- data.frame(
    scope_id      = 1L,
    scope_level_1 = "LISA",
    release       = "2021",
    stringsAsFactors = FALSE
  )
  # depth=1 ok
  expect_silent(validate_scope(df, scope_depth = 1L))
  # depth=2 missing scope_level_2
  expect_error(validate_scope(df, scope_depth = 2L),
               class = "rs_error_schema")
})


test_that("load_bundle() loads full v3 bundle when all 5 files present", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir_ <- file.path(tmp, "autolabel", "scb")
  dir.create(dir_, recursive = TRUE)
  write_manifest_csv(dir_, "scb", "eng", scope_depth = 2L)
  write_bundle_files(dir_, "eng", scope_depth = 2L)

  bundle <- load_bundle("scb", "eng")

  expect_s3_class(bundle, "rs_bundle")
  expect_false(bundle$core_only)
  expect_identical(nrow(bundle$variables), 2L)
  expect_identical(nrow(bundle$value_labels), 1L)
  expect_identical(nrow(bundle$scope), 2L)
  expect_identical(nrow(bundle$release_sets), 2L)
  expect_identical(bundle$manifest$scope_depth, 2L)
})


test_that("load_bundle() synthesises core-only manifest when absent", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir_ <- file.path(tmp, "autolabel", "scb")
  dir.create(dir_, recursive = TRUE)
  # Write only variables + value_labels, no manifest/scope/release_sets
  vars <- data.frame(
    variable_name  = "age",
    variable_label = "Age",
    variable_type  = "continuous",
    release_set_id = 1L,
    stringsAsFactors = FALSE
  )
  vlabs <- data.frame(
    value_label_id     = "none",
    value_labels_json  = "{}",
    value_labels_stata = "",
    code_count         = 0L,
    stringsAsFactors = FALSE
  )
  utils::write.table(vars, file.path(dir_, "variables_eng.csv"),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")
  utils::write.table(vlabs, file.path(dir_, "value_labels_eng.csv"),
                     sep = ";", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, fileEncoding = "UTF-8")

  bundle <- load_bundle("scb", "eng")
  expect_true(bundle$core_only)
  expect_identical(bundle$manifest$scope_depth, 0L)
  expect_null(bundle$scope)
  expect_null(bundle$release_sets)
})


test_that("load_bundle() raises rs_error_missing_bundle when variables absent", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  expect_error(load_bundle("scb", "eng"),
               class = "rs_error_missing_bundle")
})


test_that("migrate_legacy_cache() moves flat-layout files into per-domain dirs", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  base <- file.path(tmp, "autolabel")
  dir.create(base, recursive = TRUE)

  # Drop two flat-layout files
  file.create(file.path(base, "scb_variables_eng.dta"))
  file.create(file.path(base, "scb_value_labels_eng.csv"))
  file.create(file.path(base, "dst_variables_dan.dta"))
  # And one sibling that must NOT be moved
  file.create(file.path(base, "datasets.csv"))

  moved <- migrate_legacy_cache()
  expect_identical(moved, 3L)

  expect_true(file.exists(file.path(base, "scb", "variables_eng.dta")))
  expect_true(file.exists(file.path(base, "scb", "value_labels_eng.csv")))
  expect_true(file.exists(file.path(base, "dst", "variables_dan.dta")))
  expect_true(file.exists(file.path(base, "datasets.csv")))  # untouched

  # Idempotent second call
  moved2 <- migrate_legacy_cache()
  expect_identical(moved2, 0L)
})


test_that("bundle_filename() produces per-domain-relative names", {
  expect_identical(bundle_filename("variables", "eng"),
                   "variables_eng.dta")
  expect_identical(bundle_filename("values", "swe", ext = "csv"),
                   "value_labels_swe.csv")
  expect_identical(bundle_filename("manifest", "eng", ext = "csv"),
                   "manifest_eng.csv")
  expect_identical(bundle_filename("scope", "eng"),
                   "scope_eng.dta")
  expect_identical(bundle_filename("release_sets", "eng"),
                   "release_sets_eng.dta")
})


test_that("bundle_path() uses per-domain subdirectory", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  path <- bundle_path("scb", "variables", "eng", ext = "dta")
  expect_match(normalizePath(dirname(path), winslash = "/", mustWork = FALSE),
               "autolabel/scb$")
  expect_identical(basename(path), "variables_eng.dta")
})
