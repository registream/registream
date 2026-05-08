# registream (R port) — NEWS

## registream 3.0.1 (2026-05-08)

R-port-only patch. Stata and Python clients are unaffected.

### Bug fixes

- **`parse_value_labels_stata(type = "character")` now filters integer-coded entries when the metadata mixes integer and string codes.** SCB's CIVIL variable carries both numeric ("1"/"2"/"3"/...) and Swedish ("OG"/"G"/"S"/"Ä") codes pointing to the same English label strings. When a user's CIVIL column was character-typed, the parser previously returned every entry — coercing integer codes to strings — which produced a labels vector with duplicate names like `c(Single = "1", Married = "2", Single = "OG", Married = "G")`. `haven::labelled()` then rejected it with *"labels must be unique"*. The character branch now mirrors the integer branch's `valid_int` filter and returns only string-coded entries when both types are present, falling back to coercing all codes when only integer codes exist (preserves the existing all-integer test case).

### Tests

- New test in `test-parse_stata_labels.R` for the mixed-coded character case.
- Pre-existing namespace failures fixed: `read_metadata_csv`, `warn_invalid_variable_types`, and `STATA_EPOCH` now qualified with `registream:::` in tests; three `local_mocked_bindings` calls in `test-updates.R` now pass `.package = "registream"`. Suite runs green under `R CMD INSTALL` + `testthat::test_dir`, not only under `devtools::test()`.


## registream 3.0.0 (2026-04-08)

First public release of the R port. See the ecosystem [`CHANGELOG.md`](../CHANGELOG.md) at the registream repo root for the v3.0.0 release notes.
