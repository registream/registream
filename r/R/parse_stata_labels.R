# Stata value-label string parser.
#
# Line-for-line port of `parse_value_labels_stata` and `_stata_tokenize`
# from registream-autolabel's `_labels.py:73-169` (Python). The on-disk
# format in the shared metadata cache uses Stata word-parsing: alternating
# code/label tokens, each either a double-quoted string (with `""` as the
# escape for an embedded `"`) or a bare whitespace-separated word.
#
#   "1" "Male" "2" "Female"
#   "K" "Woman" "M" "Man" "1" "Man" "2" "Woman"
#
# The R port's one semantic difference from Python is the NAMED-VECTOR
# FLIP. Python returns `{code: label}` (key = code, value = label). R
# returns a named vector with `name = label, value = code`. This matches
# the `haven::labelled()` convention for the `labels` argument:
#
#   Python: {1: "Male", 2: "Female"}
#   R:      c(Male = 1L, Female = 2L)
#
# A single metadata string can mix integer and character codes (e.g. the
# `kon` example from `autolabel.ado` line 505 where both "K"/"M" and
# "1"/"2" codes coexist). In that case we cannot return a single named
# vector because R vectors are homogeneous. Instead `type = "auto"`
# returns a list with both slots populated:
#
#   list(
#     integer   = c(Man = 1L, Woman = 2L),
#     character = c(Woman = "K", Man = "M")
#   )
#
# The caller (autolabel's label-application step) picks the slot matching
# `typeof(col)` for the target column. `type = "integer"` or
# `type = "character"` force a single-vector return and filter out codes
# that don't match the requested type.

parse_value_labels_stata <- function(s, type = c("auto", "integer", "character")) {
  type <- match.arg(type)

  if (is.null(s)) return(empty_labels(type))
  if (length(s) == 0L) return(empty_labels(type))
  if (length(s) > 1L) s <- s[[1L]]
  if (is.na(s)) return(empty_labels(type))

  text <- trimws(as.character(s))
  if (!nzchar(text)) return(empty_labels(type))

  tokens <- stata_tokenize(text)
  if (length(tokens) < 2L) return(empty_labels(type))

  # Iterate by pairs; odd trailing token is silently dropped, matching
  # Stata's `forval k = 1(2)nwords` loop which stops at the last
  # complete pair.
  n_pairs <- length(tokens) %/% 2L
  idx_code  <- seq.int(1L, 2L * n_pairs, by = 2L)
  idx_label <- seq.int(2L, 2L * n_pairs, by = 2L)
  code_strs <- tokens[idx_code]
  labels    <- tokens[idx_label]

  # A code is an "integer" iff it matches Python `int()` parse semantics.
  # Regex is strict on purpose: `1.0` and `K` must stay as strings.
  # `[+-]?` mirrors Python's acceptance of `+1` and `-99`.
  valid_int <- grepl("^[+-]?[0-9]+$", code_strs)
  code_ints <- suppressWarnings(as.integer(code_strs))
  valid_int <- valid_int & !is.na(code_ints)

  if (type == "integer") {
    if (!any(valid_int)) return(empty_labels("integer"))
    return(stats::setNames(code_ints[valid_int], labels[valid_int]))
  }
  if (type == "character") {
    # Symmetric to the `integer` branch: when the metadata mixes
    # integer-coded and string-coded entries (SCB's `CIVIL` carries both
    # numeric "1"/"2" and Swedish "OG"/"G"/"S" codes with the SAME label
    # strings), apply-time receives a character column and only the
    # string-coded entries can match. Returning every entry coerced to
    # string produced duplicate label names, which `haven::labelled()`
    # rejects with "labels must be unique". When there are NO character
    # codes (all-integer metadata, e.g. the existing parser test), fall
    # back to coercing every code to string so the labels still apply.
    if (any(!valid_int)) {
      return(stats::setNames(code_strs[!valid_int], labels[!valid_int]))
    }
    return(stats::setNames(code_strs, labels))
  }

  # type == "auto": pure-integer, pure-character, or mixed.
  if (all(valid_int)) {
    return(stats::setNames(code_ints, labels))
  }
  if (!any(valid_int)) {
    return(stats::setNames(code_strs, labels))
  }
  list(
    integer   = stats::setNames(code_ints[valid_int],  labels[valid_int]),
    character = stats::setNames(code_strs[!valid_int], labels[!valid_int])
  )
}

empty_labels <- function(type) {
  if (type == "character") {
    return(stats::setNames(character(0), character(0)))
  }
  stats::setNames(integer(0), character(0))
}

stata_tokenize <- function(s) {
  chars <- strsplit(s, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  if (n == 0L) return(character(0))

  # Precompute whitespace / quote masks once; avoids per-char regex.
  is_ws <- chars %in% c(" ", "\t", "\n", "\r", "\v", "\f")
  is_q  <- chars == '"'

  tokens <- character(0)
  i <- 1L

  while (i <= n) {
    while (i <= n && is_ws[i]) i <- i + 1L
    if (i > n) break

    if (is_q[i]) {
      # Quoted token: read until matching `"`, with `""` as escape.
      i <- i + 1L
      buf_start <- i
      buf_parts <- character(0)
      while (i <= n) {
        if (is_q[i]) {
          if (i + 1L <= n && is_q[i + 1L]) {
            # Escaped quote: flush literal run, append one `"`, skip both.
            if (i > buf_start) {
              buf_parts <- c(buf_parts,
                             paste(chars[buf_start:(i - 1L)], collapse = ""))
            }
            buf_parts <- c(buf_parts, '"')
            i <- i + 2L
            buf_start <- i
          } else {
            # Closing quote.
            if (i > buf_start) {
              buf_parts <- c(buf_parts,
                             paste(chars[buf_start:(i - 1L)], collapse = ""))
            }
            i <- i + 1L
            break
          }
        } else {
          i <- i + 1L
        }
      }
      tokens <- c(tokens, paste(buf_parts, collapse = ""))
    } else {
      # Bare token: read until next whitespace.
      start <- i
      while (i <= n && !is_ws[i]) i <- i + 1L
      tokens <- c(tokens, paste(chars[start:(i - 1L)], collapse = ""))
    }
  }

  tokens
}
