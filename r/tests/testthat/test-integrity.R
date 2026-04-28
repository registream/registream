test_that("check_integrity() is a no-op when datasets.csv is absent", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  fake_dta <- file.path(tmp, "autolabel", "scb_variables_eng.dta")
  dir.create(dirname(fake_dta), recursive = TRUE)
  writeLines("stub content", fake_dta)

  expect_silent(
    registream:::check_integrity("scb", "variables", "eng", fake_dta,
                                  directory = tmp)
  )
})


test_that("check_integrity() is a no-op when the key has no entry", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir.create(file.path(tmp, "autolabel"), recursive = TRUE)
  registry <- file.path(tmp, "autolabel", "datasets.csv")
  writeLines(
    c("dataset_key;domain;type;lang;version;schema;downloaded;source;file_size_dta;file_size_csv;last_checked",
      "scb_registers_eng;scb;registers;eng;20260309;2.0;0;api;1000;500;0"),
    registry
  )

  fake_dta <- file.path(tmp, "autolabel", "scb_variables_eng.dta")
  writeLines("stub", fake_dta)

  expect_silent(
    registream:::check_integrity("scb", "variables", "eng", fake_dta,
                                  directory = tmp)
  )
})


test_that("check_integrity() passes when stored file_size_dta matches actual", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir.create(file.path(tmp, "autolabel"), recursive = TRUE)
  fake_dta <- file.path(tmp, "autolabel", "scb_variables_eng.dta")
  writeLines("exactly eleven", fake_dta)
  actual_size <- file.info(fake_dta)$size

  registry <- file.path(tmp, "autolabel", "datasets.csv")
  writeLines(
    c("dataset_key;domain;type;lang;version;schema;downloaded;source;file_size_dta;file_size_csv;last_checked",
      sprintf("scb_variables_eng;scb;variables;eng;20260309;2.0;0;api;%d;0;0", actual_size)),
    registry
  )

  expect_silent(
    registream:::check_integrity("scb", "variables", "eng", fake_dta,
                                  directory = tmp)
  )
})


test_that("check_integrity() raises rs_error_integrity on size mismatch", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir.create(file.path(tmp, "autolabel"), recursive = TRUE)
  fake_dta <- file.path(tmp, "autolabel", "scb_variables_eng.dta")
  writeLines("some content", fake_dta)

  registry <- file.path(tmp, "autolabel", "datasets.csv")
  writeLines(
    c("dataset_key;domain;type;lang;version;schema;downloaded;source;file_size_dta;file_size_csv;last_checked",
      "scb_variables_eng;scb;variables;eng;20260309;2.0;0;api;9999999;0;0"),
    registry
  )

  err <- tryCatch(
    registream:::check_integrity("scb", "variables", "eng", fake_dta,
                                  directory = tmp),
    error = function(e) e
  )
  expect_s3_class(err, "rs_error_integrity")
  expect_match(conditionMessage(err), "integrity check failed", fixed = TRUE)
  expect_match(conditionMessage(err), "Expected size: 9999999", fixed = TRUE)
})


test_that("check_integrity() skips when stored size is 0 or blank", {
  tmp <- withr::local_tempdir()
  withr::local_envvar(REGISTREAM_DIR = tmp)

  dir.create(file.path(tmp, "autolabel"), recursive = TRUE)
  fake_dta <- file.path(tmp, "autolabel", "scb_variables_eng.dta")
  writeLines("content", fake_dta)

  registry <- file.path(tmp, "autolabel", "datasets.csv")
  writeLines(
    c("dataset_key;domain;type;lang;version;schema;downloaded;source;file_size_dta;file_size_csv;last_checked",
      "scb_variables_eng;scb;variables;eng;20260309;2.0;0;api;0;0;0"),
    registry
  )

  expect_silent(
    registream:::check_integrity("scb", "variables", "eng", fake_dta,
                                  directory = tmp)
  )
})
