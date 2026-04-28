# Schema validation tests: v3 bundle only (schema_version = "2.0",
# 5-file layout).

valid_manifest <- function(scope_depth = 2L) {
  rows <- c(
    "domain",              "scb",
    "schema_version",      "2.0",
    "publisher",           "SCB",
    "bundle_release_date", "2026-04-17",
    "languages",           "eng",
    "scope_depth",         as.character(scope_depth)
  )
  for (i in seq_len(scope_depth)) {
    rows <- c(rows,
              sprintf("scope_level_%d_name", i), sprintf("level%d", i),
              sprintf("scope_level_%d_title", i), sprintf("Level %d", i))
  }
  mat <- matrix(rows, ncol = 2L, byrow = TRUE)
  data.frame(key = mat[, 1L], value = mat[, 2L], stringsAsFactors = FALSE)
}


valid_variables <- function() {
  data.frame(
    variable_name  = c("age", "sex"),
    variable_label = c("Age", "Sex"),
    variable_type  = c("continuous", "categorical"),
    release_set_id = c(1L, 1L),
    stringsAsFactors = FALSE
  )
}


valid_value_labels <- function() {
  data.frame(
    value_label_id     = "sex_lbl",
    value_labels_json  = '{"1":"Male","2":"Female"}',
    value_labels_stata = '"1" "Male" "2" "Female"',
    code_count         = 2L,
    stringsAsFactors = FALSE
  )
}


valid_scope <- function(scope_depth = 2L) {
  df <- data.frame(
    scope_id      = c(1L, 2L),
    scope_level_1 = c("LISA", "BR"),
    release       = c("2021", "2020"),
    stringsAsFactors = FALSE
  )
  if (scope_depth >= 2L) df$scope_level_2 <- c("Individer", "Barn")
  df
}


valid_release_sets <- function() {
  data.frame(
    release_set_id = c(1L, 2L),
    scope_id       = c(1L, 2L),
    stringsAsFactors = FALSE
  )
}


test_that("validate_schema('variables') passes on v3 shape", {
  expect_invisible(validate_schema(valid_variables(), "variables"))
})


test_that("validate_schema('values') passes on v3 value-labels shape", {
  expect_invisible(validate_schema(valid_value_labels(), "values"))
})


test_that("validate_schema('scope', scope_depth = N) enforces level columns", {
  sc <- valid_scope(scope_depth = 2L)
  expect_invisible(validate_schema(sc, "scope", scope_depth = 2L))

  # Asking for depth 3 on a depth-2 scope fails
  expect_error(validate_schema(sc, "scope", scope_depth = 3L),
               class = "rs_error_schema")
})


test_that("validate_schema('release_sets') enforces required columns", {
  expect_invisible(validate_schema(valid_release_sets(), "release_sets"))

  bad <- valid_release_sets()
  bad$scope_id <- NULL
  expect_error(validate_schema(bad, "release_sets"),
               class = "rs_error_schema")
})


test_that("validate_schema('manifest') returns rs_manifest on valid input", {
  m <- validate_schema(valid_manifest(), "manifest")
  expect_s3_class(m, "rs_manifest")
  expect_identical(m$scope_depth, 2L)
})


test_that("validate_schema('manifest') rejects non-'2.0' schema_version", {
  df <- valid_manifest()
  df$value[df$key == "schema_version"] <- "1.0"
  expect_error(validate_schema(df, "manifest"),
               class = "rs_error_schema")
})


test_that("variables missing a required column raises rs_error_schema", {
  df <- valid_variables()
  df$variable_label <- NULL
  expect_error(validate_schema(df, "variables"),
               regexp = "variable_label",
               class = "rs_error_schema")
})


test_that("value_labels missing a required column raises rs_error_schema", {
  df <- valid_value_labels()
  df$value_labels_stata <- NULL
  expect_error(validate_schema(df, "values"),
               class = "rs_error_schema")
})


test_that("warn_invalid_variable_types counts non-standard types", {
  df <- valid_variables()
  df$variable_type <- c("continuous", "unknownweirdtype")
  expect_equal(warn_invalid_variable_types(df), 1L)
})


test_that("warn_invalid_variable_types returns 0 when column missing", {
  df <- valid_variables()
  df$variable_type <- NULL
  expect_equal(warn_invalid_variable_types(df), 0L)
})
