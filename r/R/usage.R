# Per-client usage logging: appends to `usage_r.csv` when enabled.
#
# Mirrors registream/usage.py with one difference: the user_id hash is
# computed via digest::digest(..., "sha256") in R instead of hashlib.sha256
# in Python. The truncated 16-character hashes are NOT comparable across
# clients (different inputs to compute_user_id would be), but the
# `username + hostname + salt` triple is identical, so the resulting
# hashes match byte-for-byte as long as both clients read the same salt
# file). The salt file (`.salt`) is shared with the Python and Stata
# clients when the three files co-locate in REGISTREAM_DIR.
#
# File layout: usage_r.csv, .salt, and config_r.toml all live in the same
# `registream_config_dir()` so they co-locate with `usage_python.csv` /
# `config_python.toml` / `.salt` when REGISTREAM_DIR is set, matching
# the Python/Stata single-directory layout.

USAGE_FILENAME <- "usage_r.csv"
SALT_FILENAME  <- ".salt"
USAGE_HEADER   <- c(
  "timestamp",
  "user_id",
  "platform",
  "module",
  "module_version",
  "core_version",
  "command_string",
  "os",
  "platform_version"
)


usage_path <- function(directory = NULL) {
  file.path(registream_config_dir(directory), USAGE_FILENAME)
}


usage_init <- function(directory = NULL) {
  dir_ <- registream_config_dir(directory)
  dir.create(dir_, recursive = TRUE, showWarnings = FALSE)

  ensure_salt(dir_)

  path <- file.path(dir_, USAGE_FILENAME)
  header_line <- paste(USAGE_HEADER, collapse = ";")

  if (!file.exists(path)) {
    writeLines(header_line, path)
    return(invisible(path))
  }

  # Rotate pre-9-col schemas aside. Matches the Stata pattern in
  # _rs_usage.ado:48-60: any header mismatch ships the old file to
  # `.old` and starts fresh, so a client upgrade never corrupts the log.
  existing <- tryCatch(readLines(path, n = 1L, warn = FALSE),
                       error = function(e) character(0))
  if (length(existing) == 0L || !identical(existing[[1L]], header_line)) {
    old_path <- paste0(path, ".old")
    suppressWarnings(file.remove(old_path))
    file.rename(path, old_path)
    writeLines(header_line, path)
  }

  invisible(path)
}


usage_log <- function(command,
                      module,
                      module_version,
                      core_version,
                      directory = NULL) {
  dir_ <- registream_config_dir(directory)

  cfg <- config_load(dir_)
  if (!isTRUE(cfg$usage_logging)) {
    return(invisible(NULL))
  }

  usage_init(dir_)

  row <- c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    compute_user_id(dir_),
    "r",
    as.character(module),
    as.character(module_version),
    as.character(core_version),
    as.character(command),
    Sys.info()[["sysname"]],
    as.character(getRversion())
  )

  # Escape any embedded ';' so the delimited format doesn't break. The
  # Python side doesn't escape (it uses csv.writer which quotes fields
  # containing ';'), but we emit a simpler format: the escape is a
  # belt-and-braces measure for pathological command strings. Command
  # strings in practice are short identifiers ("autolabel", "rs_lookup").
  row <- gsub(";", ",", row, fixed = TRUE)

  line <- paste(row, collapse = ";")
  path <- file.path(dir_, USAGE_FILENAME)
  cat(line, "\n", file = path, append = TRUE, sep = "")

  invisible(NULL)
}


rs_stats <- function(directory = NULL, all_users = FALSE) {
  dir_ <- registream_config_dir(directory)
  path <- file.path(dir_, USAGE_FILENAME)

  if (!file.exists(path)) {
    uid <- if (file.exists(file.path(dir_, SALT_FILENAME))) {
      compute_user_id(dir_)
    } else {
      ""
    }
    return(structure(
      list(
        user_id      = uid,
        total_calls  = 0L,
        unique_users = 0L,
        first_use    = as.POSIXct(NA, tz = "UTC"),
        last_use     = as.POSIXct(NA, tz = "UTC")
      ),
      class = "registream_usage_stats"
    ))
  }

  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(lines) <= 1L) {
    uid <- compute_user_id(dir_)
    return(structure(
      list(
        user_id      = uid,
        total_calls  = 0L,
        unique_users = 0L,
        first_use    = as.POSIXct(NA, tz = "UTC"),
        last_use     = as.POSIXct(NA, tz = "UTC")
      ),
      class = "registream_usage_stats"
    ))
  }

  header <- strsplit(lines[[1]], ";", fixed = TRUE)[[1]]
  rows <- lapply(lines[-1L], function(raw) {
    fields <- strsplit(raw, ";", fixed = TRUE)[[1]]
    if (length(fields) < length(header)) {
      fields <- c(fields, rep("", length(header) - length(fields)))
    }
    stats::setNames(as.list(fields[seq_along(header)]), header)
  })

  uid <- compute_user_id(dir_)
  all_user_ids <- vapply(rows, function(r) r$user_id %||% "", character(1))
  unique_users <- length(unique(all_user_ids[nzchar(all_user_ids)]))

  if (!isTRUE(all_users)) {
    rows <- rows[all_user_ids == uid]
  }

  total_calls <- length(rows)
  first_use <- as.POSIXct(NA, tz = "UTC")
  last_use  <- as.POSIXct(NA, tz = "UTC")
  if (total_calls > 0L) {
    ts <- vapply(rows, function(r) r$timestamp %||% "", character(1))
    parsed <- parse_usage_timestamps(ts)
    valid <- parsed[!is.na(parsed)]
    if (length(valid) > 0L) {
      first_use <- min(valid)
      last_use  <- max(valid)
    }
  }

  structure(
    list(
      user_id      = uid,
      total_calls  = total_calls,
      unique_users = unique_users,
      first_use    = first_use,
      last_use     = last_use
    ),
    class = "registream_usage_stats"
  )
}


print.registream_usage_stats <- function(x, ...) {
  rule <- strrep("-", 60)
  cat(rule, "\n")
  cat("RegiStream Usage Statistics\n")
  cat(rule, "\n")
  cat(sprintf("  user_id:       %s\n", x$user_id))
  cat(sprintf("  total_calls:   %d\n", x$total_calls))
  cat(sprintf("  unique_users:  %d\n", x$unique_users))
  if (!is.na(x$first_use)) {
    cat(sprintf("  first_use:     %s\n",
                format(x$first_use, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")))
  }
  if (!is.na(x$last_use)) {
    cat(sprintf("  last_use:      %s\n",
                format(x$last_use, "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")))
  }
  cat(rule, "\n")
  invisible(x)
}


compute_user_id <- function(directory = NULL) {
  dir_ <- registream_config_dir(directory)
  salt <- ensure_salt(dir_)

  username <- current_username()
  hostname <- current_hostname()

  combined <- paste0(username, hostname, salt)
  hash <- digest::digest(combined, algo = "sha256", serialize = FALSE)
  substr(hash, 1, 16)
}


# ─── Internal helpers ────────────────────────────────────────────────────────

ensure_salt <- function(directory) {
  dir_ <- registream_config_dir(directory)
  salt_path <- file.path(dir_, SALT_FILENAME)

  if (!file.exists(salt_path)) {
    dir.create(dir_, recursive = TRUE, showWarnings = FALSE)
    # 64 hex chars generated from a high-entropy input. Not cryptographically
    # strong (R has no built-in CSPRNG without extra packages), but the salt
    # is hashed together with username+hostname before use, so mild randomness
    # is sufficient; the point is to produce stable but non-guessable user-id
    # hashes that differ between installations.
    seed_material <- paste(
      as.numeric(Sys.time()),
      Sys.getpid(),
      sample(.Machine$integer.max, 1L),
      sep = "|"
    )
    salt <- digest::digest(seed_material, algo = "sha256", serialize = FALSE)
    writeLines(salt, salt_path)
  }

  trimws(readLines(salt_path, warn = FALSE, n = 1L))
}


current_username <- function() {
  u <- tryCatch(Sys.info()[["user"]], error = function(e) NA_character_)
  if (!is.na(u) && nzchar(u)) return(u)
  u <- Sys.getenv("USER", unset = "")
  if (nzchar(u)) return(u)
  u <- Sys.getenv("USERNAME", unset = "")
  if (nzchar(u)) return(u)
  "unknown"
}


current_hostname <- function() {
  h <- tryCatch(Sys.info()[["nodename"]], error = function(e) NA_character_)
  if (!is.na(h) && nzchar(h)) return(h)
  "unknown"
}


parse_usage_timestamps <- function(ts) {
  out <- as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  out
}


`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
