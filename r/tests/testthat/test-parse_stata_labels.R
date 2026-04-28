# Parity tests for parse_value_labels_stata.
#
# Every test here mirrors a test in the Python suite at
# `autolabel/python/registream-autolabel/tests/test_labels.py`, with the
# expected output flipped from Python's `{code: label}` dict into R's
# `c(label = code)` named vector. If the Python test for the same input
# asserts `{1: "Male"}`, the R test asserts `c(Male = 1L)`.
#
# `parse_value_labels_stata` is unexported; we pull it from the package
# namespace so these tests work under `R CMD check` without triggering a
# `:::` note.

parse <- getFromNamespace("parse_value_labels_stata", "registream")
empty_int  <- stats::setNames(integer(0),   character(0))
empty_char <- stats::setNames(character(0), character(0))


# ── empty / NA / NULL inputs ─────────────────────────────────────────────────

test_that("empty string returns empty integer vector", {
  expect_identical(parse(""), empty_int)
})

test_that("whitespace-only string returns empty integer vector", {
  expect_identical(parse("   "), empty_int)
})

test_that("NULL returns empty integer vector", {
  expect_identical(parse(NULL), empty_int)
})

test_that("NA returns empty integer vector", {
  expect_identical(parse(NA), empty_int)
  expect_identical(parse(NA_character_), empty_int)
})


# ── happy path: integer-coded labels (named-vector flip) ─────────────────────

test_that("single quoted pair: {1: Male} becomes c(Male = 1L)", {
  expect_identical(parse('"1" "Male"'), c(Male = 1L))
})

test_that("multiple pairs flip correctly", {
  expect_identical(
    parse('"1" "Male" "2" "Female"'),
    c(Male = 1L, Female = 2L)
  )
})

test_that("negative code is preserved", {
  expect_identical(parse('"-99" "Missing"'), c(Missing = -99L))
})

test_that("integer codes produce an integer-typed vector", {
  result <- parse('"1" "A" "2" "B"')
  expect_type(result, "integer")
  expect_identical(result, c(A = 1L, B = 2L))
})


# ── string-coded labels ──────────────────────────────────────────────────────

test_that("non-integer codes stay as character", {
  result <- parse('"K" "Kvinna" "M" "Man"')
  expect_type(result, "character")
  expect_identical(result, c(Kvinna = "K", Man = "M"))
})


# ── mixed-type codes → list with both slots ──────────────────────────────────

test_that("mixed integer and character codes return a two-slot list", {
  # Python: {"K": "Woman", "M": "Man", 1: "Man", 2: "Woman"}
  # R's vectors are homogeneous, so this splits across two slots.
  result <- parse('"K" "Woman" "M" "Man" "1" "Man" "2" "Woman"')
  expect_type(result, "list")
  expect_named(result, c("integer", "character"))
  expect_identical(result$integer,   c(Man = 1L, Woman = 2L))
  expect_identical(result$character, c(Woman = "K", Man = "M"))
})


# ── whitespace tolerance and multi-word labels ───────────────────────────────

test_that("quoted labels may contain spaces", {
  expect_identical(
    parse('"1" "Married with children"'),
    c(`Married with children` = 1L)
  )
})

test_that("unquoted bare tokens parse too", {
  expect_identical(parse("1 yes 2 no"), c(yes = 1L, no = 2L))
})

test_that("mixed quoted and unquoted tokens parse together", {
  expect_identical(
    parse('1 "Yes please" 2 No'),
    c(`Yes please` = 1L, No = 2L)
  )
})

test_that("extra whitespace around tokens is tolerated", {
  expect_identical(
    parse('  "1"   "Male"   "2"   "Female"  '),
    c(Male = 1L, Female = 2L)
  )
})


# ── escaped quotes (`""` inside a quoted token) ──────────────────────────────

test_that("single escaped quote inside a label", {
  expect_identical(
    parse('"1" "Don""t know"'),
    stats::setNames(1L, 'Don"t know')
  )
})

test_that("multiple escaped quotes around a substring", {
  expect_identical(
    parse('"1" "She said ""hi"""'),
    stats::setNames(1L, 'She said "hi"')
  )
})


# ── Stata forval 1(2)nwords: odd trailing token is dropped ───────────────────

test_that("odd trailing token is silently dropped", {
  expect_identical(parse('"1" "Male" "2"'), c(Male = 1L))
})


# ── type-forcing options ─────────────────────────────────────────────────────

test_that("type = 'integer' keeps only integer-parseable codes", {
  # Same mixed input as above, but forced to integer slot.
  result <- parse('"K" "Woman" "M" "Man" "1" "Man" "2" "Woman"',
                  type = "integer")
  expect_identical(result, c(Man = 1L, Woman = 2L))
})

test_that("type = 'character' keeps codes verbatim as strings", {
  result <- parse('"1" "Male" "2" "Female"', type = "character")
  expect_identical(result, c(Male = "1", Female = "2"))
})
