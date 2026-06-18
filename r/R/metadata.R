# Shared metadata cache reader.
#
# Reads the metadata cache at `<cache_dir>/autolabel/`, shared with the
# Stata and Python clients. All three clients use the same file naming
# convention:
#
#   <domain>_variables_<lang>.dta
#   <domain>_value_labels_<lang>.dta
#   <domain>_registers_<lang>.dta
#   <domain>_*_<lang>.csv     (CSV fallback when DTA is missing)
#
# DTA is read via `haven::read_dta` (declared in Suggests; this file calls
# it through `requireNamespace` so plain `library(registream)` doesn't
# pull haven's transitive tidyverse tree). CSV fallback uses base R
# `read.csv` with semicolon delimiter.

# The autolabel cache lives under <cache_dir>/autolabel/ (Python's
# `metadata.AUTOLABEL_SUBDIR` constant. Kept as an internal name so the
# join semantics with cache_dir() are explicit.
.AUTOLABEL_SUBDIR <- "autolabel"

# Map file_type to the filename infix. Note "values" -> "value_labels"
# (Stata-side convention from `_rs_autolabel_utils.ado:244-260`). Both
# clients must produce the same filename for the same inputs or the
# shared cache breaks.
.FILENAME_INFIX <- c(
  variables    = "variables",
  values       = "value_labels",
  scope        = "scope",
  release_sets = "release_sets",
  manifest     = "manifest"
)


cache_filename <- function(domain, file_type, lang, ext = "dta") {
  if (!file_type %in% names(.FILENAME_INFIX)) {
    stop(sprintf(
      "Invalid file_type: '%s'. Must be one of: %s",
      file_type,
      paste(names(.FILENAME_INFIX), collapse = ", ")
    ), call. = FALSE)
  }
  sprintf("%s_%s_%s.%s", domain, .FILENAME_INFIX[[file_type]], lang, ext)
}


autolabel_cache_dir <- function(directory = NULL) {
  base <- if (is.null(directory)) cache_dir() else path.expand(directory)
  file.path(base, .AUTOLABEL_SUBDIR)
}


autolabel_cache_path <- function(domain, file_type, lang, ext = "dta", directory = NULL) {
  file.path(autolabel_cache_dir(directory), cache_filename(domain, file_type, lang, ext))
}


load_metadata <- function(domain, file_type, lang, directory = NULL) {
  require_haven()

  pd_dta <- bundle_path(domain, file_type, lang, ext = "dta", directory = directory)
  pd_csv <- bundle_path(domain, file_type, lang, ext = "csv", directory = directory)

  df <- NULL
  if (file.exists(pd_dta)) {
    check_integrity(domain, file_type, lang, pd_dta, directory = directory)
    df <- read_metadata_dta(pd_dta)
  } else if (file.exists(pd_csv)) {
    df <- read_metadata_csv(pd_csv)
  } else {
    stop(sprintf(
      paste0(
        "No cached metadata found for domain='%s', type='%s', lang='%s'.\n",
        "Looked for:\n  %s\n  %s\n\n",
        "To populate the cache, run:\n",
        "  rs_update_datasets(\"%s\", \"%s\")"
      ),
      domain, file_type, lang, pd_dta, pd_csv, domain, lang
    ), call. = FALSE)
  }

  df
}


# ── Integrity check ─────────────────────────────────────────────────────────
#
# Port of Python `registream.metadata._check_integrity`. On load, if
# `datasets.csv` has an entry for this file, compare the actual DTA file
# size against the stored `file_size_dta` field. Raise an `rs_error_integrity`
# condition on mismatch so callers can distinguish integrity failures from
# schema failures.
#
# Known issue (Stata-side, tracked as G1): Stata's `_utils_get_filesize`
# uses `fget()` to read the file as text lines and counts
# `strlen(line) + 1`, which is systematically wrong for binary .dta
# files. Cache entries written by the Stata client may carry incorrect
# sizes. The R client writes via `file.info()$size` so R-fetched caches
# are always accurate. Users with pre-existing Stata-written caches that
# trigger false positives should refresh via `rs_update_datasets(force = TRUE)`.

check_integrity <- function(domain, file_type, lang, file_path, directory = NULL) {
  registry_path <- file.path(autolabel_cache_dir(directory), "datasets.csv")
  if (!file.exists(registry_path)) {
    return(invisible(NULL))
  }

  infix <- .FILENAME_INFIX[[file_type]]
  key <- sprintf("%s_%s_%s", domain, infix, lang)

  rows <- tryCatch(
    utils::read.csv(
      registry_path, sep = ";", encoding = "UTF-8",
      stringsAsFactors = FALSE, check.names = FALSE, colClasses = "character"
    ),
    error = function(e) NULL
  )
  if (is.null(rows) || !"dataset_key" %in% colnames(rows)) {
    return(invisible(NULL))
  }

  match <- which(rows$dataset_key == key)
  if (length(match) == 0L) {
    return(invisible(NULL))
  }

  stored_dta <- rows$file_size_dta[[match[[1]]]]
  if (is.null(stored_dta) || is.na(stored_dta) ||
      !nzchar(stored_dta) || stored_dta == "0") {
    return(invisible(NULL))
  }

  actual_dta <- file.info(file_path)$size
  if (is.na(actual_dta)) {
    return(invisible(NULL))
  }

  stored_int <- suppressWarnings(as.numeric(stored_dta))
  if (is.na(stored_int) || stored_int != actual_dta) {
    cond <- structure(
      class = c("rs_error_integrity", "error", "condition"),
      list(
        message = sprintf(
          paste0(
            "File integrity check failed for %s.\n",
            "  Expected size: %s bytes\n",
            "  Actual size:   %s bytes\n\n",
            "The file may have been modified, corrupted, or written by ",
            "an older client with the known Stata-side filesize bug (G1).\n",
            "Re-download: rs_update_datasets(\"%s\", \"%s\", force = TRUE)"
          ),
          key, format(stored_int, scientific = FALSE),
          format(actual_dta, scientific = FALSE), domain, lang
        ),
        call = sys.call(-1)
      )
    )
    stop(cond)
  }

  invisible(NULL)
}


# ── Internal readers ─────────────────────────────────────────────────────────

read_metadata_dta <- function(path) {
  # haven::read_dta returns a tibble. Coerce to plain data.frame so
  # downstream code can rely on `[[` / `$` semantics without tibble's
  # stricter rules. We do NOT preserve haven_labelled-ness on metadata
  # columns themselves; these files describe data, they aren't data.
  as.data.frame(haven::read_dta(path))
}

read_metadata_csv <- function(path) {
  read_one <- function(sep) {
    utils::read.csv(
      path,
      sep = sep,
      encoding = "UTF-8",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      na.strings = c("NA", "")
    )
  }
  # The ecosystem convention is semicolon. A comma-delimited file (e.g. a
  # cache written by an older Stata client, before the `delimiter(";")` fix
  # in autolabel `_al_utils.ado`) read as semicolon collapses to a single
  # fused column, and the schema check then reports the first required
  # column as "missing" though it is present. Every v3 metadata file has at
  # least two required columns, so `ncol <= 1` unambiguously means the wrong
  # delimiter: re-read as comma. Header column-counting decides this, so it
  # is unaffected by embedded `;` inside quoted data fields.
  df <- read_one(";")
  if (ncol(df) <= 1L) {
    df <- read_one(",")
  }
  df
}

require_haven <- function() {
  if (!requireNamespace("haven", quietly = TRUE)) {
    stop(
      "Package 'haven' is required to read metadata files. ",
      "Install it with: install.packages(\"haven\")",
      call. = FALSE
    )
  }
}


# ── v3 bundle layer ──────────────────────────────────────────────────────────
#
# Python v3.0.0 stores the 5-file bundle under
# `<cache>/autolabel/<domain>/<infix>_<lang>.<ext>`. The v1/v2 R client
# stored flat-layout `<cache>/autolabel/<domain>_<infix>_<lang>.<ext>`.
# `migrate_legacy_cache()` moves the old layout into the new per-domain
# subdirectory on first `load_bundle()` call.
#
# Both the flat and the per-domain paths resolve through helpers kept
# side-by-side so existing `load_metadata()` callers continue to work
# during the transition.

autolabel_bundle_dir <- function(domain, directory = NULL) {
  file.path(autolabel_cache_dir(directory), domain)
}


bundle_filename <- function(file_type, lang, ext = "dta") {
  if (!file_type %in% names(.FILENAME_INFIX)) {
    stop(sprintf(
      "Invalid file_type: '%s'. Must be one of: %s",
      file_type,
      paste(names(.FILENAME_INFIX), collapse = ", ")
    ), call. = FALSE)
  }
  sprintf("%s_%s.%s", .FILENAME_INFIX[[file_type]], lang, ext)
}


bundle_path <- function(domain, file_type, lang, ext = "dta", directory = NULL) {
  file.path(autolabel_bundle_dir(domain, directory),
            bundle_filename(file_type, lang, ext))
}


# Move flat-layout files into per-domain subdirectories (idempotent).
# Returns the number of files moved. Mirrors Python
# `registream.metadata.migrate_legacy_cache`.
migrate_legacy_cache <- function(directory = NULL) {
  base <- autolabel_cache_dir(directory)
  if (!dir.exists(base)) return(0L)

  candidates <- list.files(base, full.names = TRUE, recursive = FALSE,
                           include.dirs = FALSE)
  candidates <- candidates[!file.info(candidates)$isdir]
  moved <- 0L
  for (src in candidates) {
    name <- basename(src)
    if (name %in% c("datasets.csv", ".salt") || startsWith(name, ".")) next

    stem <- tools::file_path_sans_ext(name)
    ext  <- tools::file_ext(name)
    parts <- strsplit(stem, "_", fixed = TRUE)[[1]]
    if (length(parts) < 3L) next

    domain <- parts[[1]]
    rest   <- paste(parts[-1L], collapse = "_")

    matched_infix <- NA_character_
    matched_lang  <- NA_character_
    for (infix in unname(.FILENAME_INFIX)) {
      prefix <- paste0(infix, "_")
      if (startsWith(rest, prefix)) {
        matched_infix <- infix
        matched_lang  <- substr(rest, nchar(prefix) + 1L, nchar(rest))
        break
      }
    }
    if (is.na(matched_infix) || !nzchar(matched_lang)) next

    dst_dir <- file.path(base, domain)
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
    dst <- file.path(dst_dir, sprintf("%s_%s.%s", matched_infix, matched_lang, ext))

    if (file.exists(dst)) {
      # Target already populated; drop the flat-layout duplicate.
      suppressWarnings(file.remove(src))
    } else if (file.rename(src, dst)) {
      moved <- moved + 1L
    }
  }
  invisible(moved)
}


# Synth a core-only manifest when no manifest file is on disk. Mirrors
# Python `_synth_core_only_manifest`.
synth_core_only_manifest <- function(domain, lang) {
  rs_manifest(
    domain              = domain,
    schema_version      = SCHEMA_VERSION,
    publisher           = "",
    bundle_release_date = "",
    languages           = lang,
    scope_depth         = 0L,
    level_names         = character(0),
    level_titles        = character(0),
    extra               = list()
  )
}


load_manifest <- function(domain, lang, directory = NULL) {
  path <- bundle_path(domain, "manifest", lang, ext = "csv",
                      directory = directory)
  if (!file.exists(path)) {
    stop(rs_schema_error(sprintf(
      paste0(
        "No manifest found for domain='%s', lang='%s'.\n",
        "Looked for: %s\n\n",
        "To populate the cache, run: rs_update_datasets(\"%s\", \"%s\")"
      ),
      domain, lang, path, domain, lang
    )))
  }
  validate_manifest(read_metadata_csv(path))
}


load_scope <- function(domain, lang, scope_depth = NULL, directory = NULL) {
  df <- read_bundle_file(domain, "scope", lang, directory)
  if (is.null(df)) return(NULL)
  validate_scope(df, scope_depth = scope_depth)
  df
}


load_release_sets <- function(domain, lang, directory = NULL) {
  df <- read_bundle_file(domain, "release_sets", lang, directory)
  if (is.null(df)) return(NULL)
  validate_release_sets(df)
  df
}


rs_bundle <- function(domain, lang, manifest, variables, value_labels,
                      scope, release_sets, core_only) {
  structure(
    list(
      domain        = domain,
      lang          = lang,
      manifest      = manifest,
      variables     = variables,
      value_labels  = value_labels,
      scope         = scope,
      release_sets  = release_sets,
      core_only     = isTRUE(core_only)
    ),
    class = "rs_bundle"
  )
}


#' @export
print.rs_bundle <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat(sprintf("RegiStream bundle: %s / %s %s\n",
              x$domain, x$lang,
              if (x$core_only) "(core-only)" else "(full v3)"))
  cat(rule, "\n")
  cat(sprintf("  variables:    %d rows\n", nrow(x$variables)))
  cat(sprintf("  value_labels: %d rows\n", nrow(x$value_labels)))
  if (!is.null(x$scope)) {
    cat(sprintf("  scope:        %d rows (depth=%d)\n",
                nrow(x$scope), x$manifest$scope_depth))
  }
  if (!is.null(x$release_sets)) {
    cat(sprintf("  release_sets: %d rows\n", nrow(x$release_sets)))
  }
  cat(rule, "\n")
  invisible(x)
}


load_bundle <- function(domain, lang, directory = NULL) {
  migrate_legacy_cache(directory)

  manifest_path <- bundle_path(domain, "manifest", lang, ext = "csv",
                               directory = directory)
  manifest <- if (file.exists(manifest_path)) {
    validate_manifest(read_metadata_csv(manifest_path))
  } else {
    NULL
  }

  variables <- read_bundle_file(domain, "variables", lang, directory)
  if (is.null(variables)) {
    stop(missing_bundle_error(domain, lang, "variables", directory))
  }

  value_labels <- read_bundle_file(domain, "values", lang, directory)
  if (is.null(value_labels)) {
    stop(missing_bundle_error(domain, lang, "values", directory))
  }

  scope_df <- NULL
  release_sets_df <- NULL
  core_only <- is.null(manifest)

  if (!is.null(manifest)) {
    scope_df <- read_bundle_file(domain, "scope", lang, directory)
    if (!is.null(scope_df)) {
      validate_scope(scope_df, scope_depth = manifest$scope_depth)
    }
    release_sets_df <- read_bundle_file(domain, "release_sets", lang, directory)
    if (!is.null(release_sets_df)) {
      validate_release_sets(release_sets_df)
    }
    if (is.null(scope_df) || is.null(release_sets_df)) core_only <- TRUE
  } else {
    manifest <- synth_core_only_manifest(domain, lang)
  }

  # v3 column contract on required files. Tolerant of legacy-v1 files
  # still on disk (no release_set_id / value_labels_json columns): if
  # the core-only synthesis path fired, skip strict v3 validation.
  if (!core_only) {
    validate_variables(variables)
    validate_value_labels(value_labels)
  }

  rs_bundle(
    domain       = domain,
    lang         = lang,
    manifest     = manifest,
    variables    = variables,
    value_labels = value_labels,
    scope        = scope_df,
    release_sets = release_sets_df,
    core_only    = core_only
  )
}


# ── Internal bundle I/O ──────────────────────────────────────────────────────

read_bundle_file <- function(domain, file_type, lang, directory) {
  dta <- bundle_path(domain, file_type, lang, ext = "dta", directory = directory)
  csv <- bundle_path(domain, file_type, lang, ext = "csv", directory = directory)
  if (file.exists(dta)) {
    require_haven()
    return(read_metadata_dta(dta))
  }
  if (file.exists(csv)) return(read_metadata_csv(csv))
  NULL
}


missing_bundle_error <- function(domain, lang, file_type, directory) {
  dta <- bundle_path(domain, file_type, lang, ext = "dta", directory = directory)
  csv <- bundle_path(domain, file_type, lang, ext = "csv", directory = directory)
  structure(
    class = c("rs_error_missing_bundle", "error", "condition"),
    list(
      message = sprintf(
        paste0(
          "No cached %s found for domain='%s', lang='%s'.\n",
          "Looked for:\n  %s\n  %s\n\n",
          "To populate the cache, run: rs_update_datasets(\"%s\", \"%s\")"
        ),
        file_type, domain, lang, dta, csv, domain, lang
      ),
      call = sys.call(-1L)
    )
  )
}
