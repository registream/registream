# rs_cite() / rs_cite_bibtex() pull from the generated _citation_data.R.

test_that("rs_cite() returns APA text with author + title", {
  out <- rs_cite(versioned = FALSE)
  expect_match(out, "Clark")
  expect_match(out, "Wen")
  expect_match(out, "RegiStream:")
  expect_match(out, "https://registream.org", fixed = TRUE)
})


test_that("rs_cite() includes installed registream version by default", {
  out <- rs_cite(versioned = TRUE)
  v <- as.character(utils::packageVersion("registream"))
  expect_match(out, sprintf("Version %s", v), fixed = TRUE)
})


test_that("rs_cite_bibtex() returns a @software entry", {
  out <- rs_cite_bibtex(versioned = TRUE)
  expect_match(out, "^@software")
  expect_match(out, "clark2024registream")
})
