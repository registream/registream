# Per-client configuration: TOML in `config_r.toml`.
#
# Mirrors registream/config.py field-for-field, with one R-specific
# addition (`cache_dir`) that Python doesn't need because Python's cache
# location and config location are always the same `~/.registream/`
# directory. On R the cache can live in `R_user_dir("registream", "cache")`
# (CRAN default), in `REGISTREAM_DIR` (env override, shares with Python/
# Stata), or at a user-chosen directory recorded in `cache_dir` here
# (second-tier override, written by the first-run wizard when the user
# opts into sharing).
#
# Each client has its own config file to avoid write contention:
# config_python.toml, config_stata.csv, config_r.toml. The R config lives
# at `tools::R_user_dir("registream", "config")/config_r.toml` by default,
# or inside REGISTREAM_DIR if set (so users who are already sharing a
# directory with Python/Stata find everything in one place).
#
# The TOML reader and writer are hand-rolled (~15 and ~40 lines) so the
# package does not depend on RcppTOML. The config is a flat key = value
# document; no tables, no arrays, no inline tables. That is all we need.

CONFIG_FILENAME <- "config_r.toml"


# ─── Public API ─────────────────────────────────────────────────────────────

config_path <- function(directory = NULL) {
  dir <- registream_config_dir(directory)
  file.path(dir, CONFIG_FILENAME)
}

config_defaults <- function() {
  structure(
    list(
      usage_logging              = TRUE,
      telemetry_enabled          = TRUE,
      internet_access            = TRUE,
      auto_update_check          = TRUE,
      last_update_check          = NULL,
      update_available           = FALSE,
      latest_version             = "",
      autolabel_update_available = FALSE,
      autolabel_latest_version   = "",
      datamirror_update_available = FALSE,
      datamirror_latest_version  = "",
      first_run_completed        = FALSE,
      cache_dir                  = ""
    ),
    class = "registream_config"
  )
}

config_init <- function(directory = NULL) {
  path <- config_path(directory)
  if (file.exists(path)) {
    return(config_load(directory))
  }
  cfg <- config_defaults()
  tryCatch(
    config_save(cfg, directory),
    error = function(e) invisible(NULL)  # read-only FS: return in-memory
  )
  cfg
}

config_load <- function(directory = NULL) {
  path <- config_path(directory)
  if (!file.exists(path)) {
    return(config_defaults())
  }
  raw <- parse_flat_toml(path)
  merge_config(raw)
}

config_save <- function(cfg, directory = NULL) {
  path <- config_path(directory)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_flat_toml(cfg_to_flat(cfg), path)
  invisible(cfg)
}

config_get <- function(key, directory = NULL) {
  known <- names(config_defaults())
  if (!key %in% known) {
    stop(sprintf("Unknown config key: %s", shQuote(key)), call. = FALSE)
  }
  config_load(directory)[[key]]
}

config_set <- function(key, value, directory = NULL) {
  known <- names(config_defaults())
  if (!key %in% known) {
    stop(sprintf("Unknown config key: %s", shQuote(key)), call. = FALSE)
  }
  cfg <- config_load(directory)
  cfg[[key]] <- value
  tryCatch(
    config_save(cfg, directory),
    error = function(e) {
      path <- config_path(directory)
      stop(
        sprintf(
          paste0(
            "Cannot write config: %s is read-only or inaccessible.\n",
            "Point RegiStream at a writable directory by setting the ",
            "REGISTREAM_DIR environment variable."
          ),
          path
        ),
        call. = FALSE
      )
    }
  )
}


# ─── Config directory resolution ────────────────────────────────────────────
#
# Separate from cache_dir() because the config must be resolvable without
# reading the config first (chicken-and-egg).

registream_config_dir <- function(directory = NULL) {
  if (!is.null(directory)) {
    return(path.expand(directory))
  }
  env <- Sys.getenv("REGISTREAM_DIR", unset = "")
  if (nzchar(env)) {
    return(path.expand(env))
  }
  # Detect a user-consented shared config at ~/.registream/config_r.toml.
  # Its existence proves the user previously opted into the shared dir via
  # the first-run wizard's cache-location prompt. Reading the file (or
  # checking its existence) is not a write, so this is CRAN-legal; the
  # only restricted operation is the initial write, which is gated behind
  # the interactive keystroke in rs_first_run().
  shared <- path.expand(file.path("~/.registream", CONFIG_FILENAME))
  if (file.exists(shared)) {
    return(dirname(shared))
  }
  tools::R_user_dir("registream", which = "config")
}


# ─── Merging raw TOML into a typed config record ────────────────────────────

merge_config <- function(raw) {
  cfg <- config_defaults()
  for (key in names(raw)) {
    if (!key %in% names(cfg)) next  # silently drop unknown keys
    value <- raw[[key]]
    if (key == "last_update_check" && is.character(value) && nzchar(value)) {
      value <- parse_iso8601_utc(value)
    }
    cfg[[key]] <- value
  }
  cfg
}

cfg_to_flat <- function(cfg) {
  out <- list()
  for (key in names(cfg)) {
    v <- cfg[[key]]
    if (is.null(v)) next
    if (key == "last_update_check" && inherits(v, "POSIXt")) {
      out[[key]] <- format_iso8601_utc(v)
    } else {
      out[[key]] <- v
    }
  }
  out
}

parse_iso8601_utc <- function(s) {
  as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

format_iso8601_utc <- function(t) {
  format(as.POSIXct(t, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}


# ─── Hand-rolled flat TOML reader ───────────────────────────────────────────
#
# Accepts: blank lines, # comments to EOL, `key = value` assignments.
# Values: true/false, "quoted strings", unquoted numbers, bare barewords
# fall through as strings. No tables, no arrays, no multi-line strings,
# no inline tables. That is the full grammar we need.

parse_flat_toml <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  out <- list()
  for (raw in lines) {
    line <- strip_toml_comment(raw)
    line <- trimws(line)
    if (!nzchar(line)) next
    eq <- regexpr("=", line, fixed = TRUE)
    if (eq < 1) next
    key <- trimws(substr(line, 1, eq - 1))
    val <- trimws(substr(line, eq + 1, nchar(line)))
    if (!nzchar(key)) next
    out[[key]] <- parse_flat_toml_value(val)
  }
  out
}

strip_toml_comment <- function(line) {
  # A '#' inside a quoted string is not a comment. Walk the line, tracking
  # whether we're inside a double-quoted string, and cut at the first '#'
  # outside quotes.
  chars <- strsplit(line, "", fixed = TRUE)[[1]]
  in_str <- FALSE
  for (i in seq_along(chars)) {
    ch <- chars[[i]]
    if (ch == "\"" && (i == 1 || chars[[i - 1]] != "\\")) {
      in_str <- !in_str
    } else if (ch == "#" && !in_str) {
      return(substr(line, 1, i - 1))
    }
  }
  line
}

parse_flat_toml_value <- function(val) {
  if (val == "true") return(TRUE)
  if (val == "false") return(FALSE)
  if (startsWith(val, "\"") && endsWith(val, "\"") && nchar(val) >= 2) {
    inner <- substr(val, 2, nchar(val) - 1)
    inner <- gsub("\\\"", "\"", inner, fixed = TRUE)
    inner <- gsub("\\\\", "\\", inner, fixed = TRUE)
    return(inner)
  }
  n <- suppressWarnings(as.numeric(val))
  if (!is.na(n) && !grepl("[A-Za-z]", val)) return(n)
  val  # bareword / unknown → keep as string
}


# ─── Hand-rolled flat TOML writer ───────────────────────────────────────────

write_flat_toml <- function(x, path) {
  lines <- character(0)
  for (key in names(x)) {
    v <- x[[key]]
    if (is.null(v)) next
    if (is.logical(v)) {
      if (is.na(v)) next
      lines <- c(lines, sprintf("%s = %s", key, if (v) "true" else "false"))
    } else if (is.numeric(v)) {
      if (is.na(v)) next
      lines <- c(lines, sprintf("%s = %s", key, format(v, scientific = FALSE)))
    } else if (is.character(v)) {
      if (is.na(v)) next
      esc <- gsub("\\", "\\\\", v, fixed = TRUE)
      esc <- gsub("\"", "\\\"", esc, fixed = TRUE)
      lines <- c(lines, sprintf("%s = \"%s\"", key, esc))
    }
    # Unknown types silently skipped.
  }
  writeLines(lines, path, useBytes = TRUE)
}
