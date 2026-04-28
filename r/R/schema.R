# Schema validation for v3 bundles (schema_version = "2.0").
#
# Line-for-line port of `registream-core/src/registream/schema.py`.
# Every bundle consists of five files: manifest, variables,
# value_labels, scope, release_sets. Each has a strict column
# contract enforced here.

SCHEMA_VERSION <- "2.0"

MANIFEST_REQUIRED_COLUMNS     <- c("key", "value")
VARIABLES_REQUIRED_COLUMNS    <- c(
  "variable_name",
  "variable_label",
  "variable_type",
  "release_set_id"
)
VALUE_LABELS_REQUIRED_COLUMNS <- c(
  "value_label_id",
  "value_labels_json",
  "value_labels_stata",
  "code_count"
)
SCOPE_REQUIRED_COLUMNS        <- c("scope_id", "scope_level_1", "release")
RELEASE_SETS_REQUIRED_COLUMNS <- c("release_set_id", "scope_id")

VALID_VARIABLE_TYPES <- c(
  "categorical", "continuous", "text", "date", "identifier", "binary", ""
)


rs_schema_error <- function(message) {
  structure(
    class = c("rs_error_schema", "error", "condition"),
    list(message = message, call = sys.call(-1L))
  )
}


warn_invalid_variable_types <- function(df) {
  if (!"variable_type" %in% colnames(df)) return(0L)
  types <- df[["variable_type"]]
  types[is.na(types)] <- ""
  types <- as.character(types)
  sum(!types %in% VALID_VARIABLE_TYPES)
}


# ── v3 bundle validators ─────────────────────────────────────────────────────

rs_manifest <- function(domain,
                        schema_version,
                        publisher,
                        bundle_release_date,
                        languages,
                        scope_depth,
                        level_names,
                        level_titles,
                        extra = list()) {
  structure(
    list(
      domain              = domain,
      schema_version      = schema_version,
      publisher           = publisher,
      bundle_release_date = bundle_release_date,
      languages           = languages,
      scope_depth         = as.integer(scope_depth),
      level_names         = as.character(level_names),
      level_titles        = as.character(level_titles),
      extra               = extra
    ),
    class = "rs_manifest"
  )
}


#' @export
print.rs_manifest <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat(sprintf("RegiStream manifest (domain=%s, schema=%s)\n",
              x$domain, x$schema_version))
  cat(rule, "\n")
  cat(sprintf("  publisher:           %s\n", x$publisher))
  cat(sprintf("  bundle_release_date: %s\n", x$bundle_release_date))
  cat(sprintf("  languages:           %s\n",
              paste(x$languages, collapse = ", ")))
  cat(sprintf("  scope_depth:         %d\n", x$scope_depth))
  if (x$scope_depth > 0L) {
    for (i in seq_len(x$scope_depth)) {
      cat(sprintf("    level %d: %s (%s)\n",
                  i, x$level_names[[i]], x$level_titles[[i]]))
    }
  }
  if (length(x$extra) > 0L) {
    cat(sprintf("  extra keys:          %s\n",
                paste(names(x$extra), collapse = ", ")))
  }
  cat(rule, "\n")
  invisible(x)
}


validate_schema_version <- function(schema_version) {
  if (is.null(schema_version) || is.na(schema_version) ||
      !nzchar(schema_version)) {
    stop(rs_schema_error(paste0(
      "No schema version found in autolabel bundle.\n",
      "autolabel requires schema_version = \"", SCHEMA_VERSION, "\".\n",
      "Solution: delete the cache directory and re-run rs_update_datasets()."
    )))
  }
  if (schema_version != SCHEMA_VERSION) {
    stop(rs_schema_error(sprintf(
      paste0(
        "Schema version mismatch.\n",
        "  Found:    %s\n",
        "  Required: %s\n\n",
        "Solution: delete the cache directory and re-run rs_update_datasets()."
      ),
      schema_version, SCHEMA_VERSION
    )))
  }
}


validate_manifest <- function(df) {
  for (col in MANIFEST_REQUIRED_COLUMNS) {
    if (!col %in% colnames(df)) {
      stop(rs_schema_error(sprintf(
        "manifest file missing required column '%s'; expected columns %s.",
        col, paste(shQuote(MANIFEST_REQUIRED_COLUMNS), collapse = ", ")
      )))
    }
  }

  keys   <- trimws(as.character(df[["key"]]))
  values <- as.character(df[["value"]])
  values[is.na(values)] <- ""
  values <- trimws(values)
  kv <- stats::setNames(values, keys)

  require_key <- function(key) {
    if (!key %in% names(kv) || !nzchar(kv[[key]])) {
      stop(rs_schema_error(sprintf("manifest missing required key '%s'.", key)))
    }
    kv[[key]]
  }

  schema_version <- require_key("schema_version")
  validate_schema_version(schema_version)

  domain              <- require_key("domain")
  publisher           <- require_key("publisher")
  bundle_release_date <- require_key("bundle_release_date")
  languages_raw       <- require_key("languages")
  languages <- Filter(nzchar,
                      trimws(strsplit(languages_raw, "|", fixed = TRUE)[[1]]))

  depth_raw <- require_key("scope_depth")
  scope_depth <- suppressWarnings(as.integer(depth_raw))
  if (is.na(scope_depth)) {
    stop(rs_schema_error(sprintf(
      "manifest key 'scope_depth' must be an integer, got '%s'.", depth_raw
    )))
  }
  if (scope_depth < 1L) {
    stop(rs_schema_error(sprintf(
      "manifest key 'scope_depth' must be >= 1, got %d.", scope_depth
    )))
  }

  level_names  <- character(scope_depth)
  level_titles <- character(scope_depth)
  for (i in seq_len(scope_depth)) {
    level_names[[i]]  <- require_key(sprintf("scope_level_%d_name", i))
    level_titles[[i]] <- require_key(sprintf("scope_level_%d_title", i))
  }

  known <- c(
    "domain", "schema_version", "publisher", "bundle_release_date",
    "languages", "scope_depth",
    sprintf("scope_level_%d_name", seq_len(scope_depth)),
    sprintf("scope_level_%d_title", seq_len(scope_depth))
  )
  extra <- as.list(kv[!names(kv) %in% known])

  rs_manifest(
    domain              = domain,
    schema_version      = schema_version,
    publisher           = publisher,
    bundle_release_date = bundle_release_date,
    languages           = languages,
    scope_depth         = scope_depth,
    level_names         = level_names,
    level_titles        = level_titles,
    extra               = extra
  )
}


validate_scope <- function(df, scope_depth = NULL) {
  for (col in SCOPE_REQUIRED_COLUMNS) {
    if (!col %in% colnames(df)) {
      stop(rs_schema_error(sprintf(
        "scope file missing required column '%s'; expected columns %s.",
        col, paste(shQuote(SCOPE_REQUIRED_COLUMNS), collapse = ", ")
      )))
    }
  }
  if (!is.null(scope_depth)) {
    for (i in seq_len(scope_depth)) {
      col <- sprintf("scope_level_%d", i)
      if (!col %in% colnames(df)) {
        stop(rs_schema_error(sprintf(
          "scope file missing '%s'; manifest declares scope_depth=%d.",
          col, scope_depth
        )))
      }
    }
  }
  invisible(NULL)
}


validate_release_sets <- function(df) {
  for (col in RELEASE_SETS_REQUIRED_COLUMNS) {
    if (!col %in% colnames(df)) {
      stop(rs_schema_error(sprintf(
        "release_sets file missing required column '%s'; expected columns %s.",
        col, paste(shQuote(RELEASE_SETS_REQUIRED_COLUMNS), collapse = ", ")
      )))
    }
  }
  invisible(NULL)
}


validate_variables <- function(df) {
  for (col in VARIABLES_REQUIRED_COLUMNS) {
    if (!col %in% colnames(df)) {
      stop(rs_schema_error(sprintf(
        "variables file missing required column '%s' (v3 bundle schema).",
        col
      )))
    }
  }
  invisible(NULL)
}


validate_value_labels <- function(df) {
  for (col in VALUE_LABELS_REQUIRED_COLUMNS) {
    if (!col %in% colnames(df)) {
      stop(rs_schema_error(sprintf(
        "value_labels file missing required column '%s' (v3 bundle schema).",
        col
      )))
    }
  }
  invisible(NULL)
}


# Dispatch wrapper: file_type ∈ {"manifest", "variables", "values",
# "scope", "release_sets"}. `scope_depth` is threaded into the scope
# validator when the manifest has already been parsed.
validate_schema <- function(df, file_type, scope_depth = NULL) {
  file_type <- match.arg(
    file_type,
    c("manifest", "variables", "values", "scope", "release_sets")
  )
  switch(
    file_type,
    manifest     = validate_manifest(df),
    variables    = validate_variables(df),
    values       = validate_value_labels(df),
    scope        = validate_scope(df, scope_depth = scope_depth),
    release_sets = validate_release_sets(df)
  )
}
