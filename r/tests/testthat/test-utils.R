test_that("get_api_host() defaults to the production host", {
  withr::local_envvar(REGISTREAM_API_HOST = NA)
  expect_identical(get_api_host(), "https://registream.org")
})


test_that("get_api_host() honors REGISTREAM_API_HOST when set", {
  withr::local_envvar(REGISTREAM_API_HOST = "https://dev.example.com")
  expect_identical(get_api_host(), "https://dev.example.com")
})


test_that("escape_ascii() applies the full q-code table", {
  expect_identical(escape_ascii("a b"),          "aq32b")
  expect_identical(escape_ascii("a.b"),          "aq46b")
  expect_identical(escape_ascii("a/b"),          "aq47b")
  expect_identical(escape_ascii("a-b"),          "aq45b")
  expect_identical(escape_ascii("a_b"),          "aq95b")
  expect_identical(escape_ascii("a*b"),          "aq42b")
  expect_identical(escape_ascii("a&b"),          "aq38b")
  expect_identical(escape_ascii("a[b]"),         "aq91bq93")
  expect_identical(escape_ascii("a{b}"),         "aq123bq125")
})


test_that("escape_ascii() matches the Python output for combined input", {
  # Same string round-tripped through the Python client produces the same
  # result. This is a fixed reference value; if it drifts the shared
  # metadata cache breaks.
  expect_identical(escape_ascii("SCB Year_2020"), "SCBq32Yearq952020")
  expect_identical(escape_ascii("foo.bar-baz"),   "fooq46barq45baz")
})


test_that("escape_ascii() leaves unaffected characters alone", {
  expect_identical(escape_ascii("abc123"), "abc123")
  expect_identical(escape_ascii(""), "")
})
