# HTTP heartbeat / update check. Mirrors registream/updates.py.
#
# Hits `<api_host>/api/v1/heartbeat` with the current package version,
# parses a plain-text `key=value\n` response, and caches results in the
# config file's `last_update_check` field for 24 hours.
#
# Behaviour delta vs the Python client:
#
# - **`rs_update()` is interactive-only.** CRAN policy forbids package
#   self-modification. The R update helper prints an `install.packages`
#   command and optionally runs it after an explicit y/N prompt.
#
# POST batch upload (Phase 7, v3.0.0 parity):
#
# When telemetry is enabled AND there are pending usage rows newer than
# `last_update_check`, `send_heartbeat` POSTs a JSON body with the
# backlog matching the Python payload shape:
#
#     {"format": "stata", "registream": "X.Y.Z",
#      "usage": [{col: val, ...}, ...]}
#
# On POST failure (405, network error) we fall back to the GET path so
# per-command telemetry still flows. The GET path remains the default
# when there is no backlog; single-command tagging doesn't justify the
# POST overhead.

HEARTBEAT_PATH <- "/api/v1/heartbeat"
CACHE_HOURS    <- 24
NETWORK_TIMEOUT_SECONDS <- 10


# ─── Public API ─────────────────────────────────────────────────────────────

send_heartbeat <- function(version,
                           command,
                           directory = NULL,
                           autolabel_version = NULL,
                           datamirror_version = NULL) {
  dir_ <- registream_config_dir(directory)
  cfg  <- config_load(dir_)

  if (!isTRUE(cfg$internet_access)) {
    return(heartbeat_result(reason = "internet_disabled"))
  }

  # 24-hour cache check.
  if (isTRUE(cfg$auto_update_check) && !is.null(cfg$last_update_check)) {
    now  <- Sys.time()
    last <- cfg$last_update_check
    if (difftime(now, last, units = "hours") < CACHE_HOURS) {
      # Rehydrate per-module cache fields so the caller can read them
      # without issuing a network call. Matches Stata's cache-hit path
      # and Python's send_heartbeat rehydration policy.
      return(heartbeat_result(
        update_available  = isTRUE(cfg$update_available),
        latest_version    = cfg$latest_version %||% "",
        autolabel_update  = isTRUE(cfg$autolabel_update_available),
        autolabel_latest  = cfg$autolabel_latest_version %||% "",
        datamirror_update = isTRUE(cfg$datamirror_update_available),
        datamirror_latest = cfg$datamirror_latest_version %||% "",
        reason            = "cached"
      ))
    }
  }

  # If neither telemetry nor update checking is enabled, no work to do.
  if (!isTRUE(cfg$telemetry_enabled) && !isTRUE(cfg$auto_update_check)) {
    return(heartbeat_result(reason = "success"))
  }

  url <- build_heartbeat_url(
    version            = version,
    command            = command,
    cfg                = cfg,
    directory          = dir_,
    autolabel_version  = autolabel_version,
    datamirror_version = datamirror_version
  )

  # POST batch path: telemetry enabled + usage rows newer than the last
  # heartbeat. Fallback to GET on any POST error (including 405 from an
  # older server). `pending` is silently empty when the usage file is
  # missing or telemetry is off.
  pending <- if (isTRUE(cfg$telemetry_enabled)) {
    tryCatch(read_pending_usage(dir_, cfg$last_update_check),
             error = function(e) data.frame())
  } else {
    data.frame()
  }

  text <- NULL
  if (is.data.frame(pending) && nrow(pending) > 0L) {
    text <- tryCatch(
      http_post_json(
        url, body = build_heartbeat_payload(version, pending),
        timeout_seconds = NETWORK_TIMEOUT_SECONDS
      ),
      error = function(e) NULL
    )
  }
  if (is.null(text)) {
    text <- tryCatch(
      http_get_text(url, timeout_seconds = NETWORK_TIMEOUT_SECONDS),
      error = function(e) NULL
    )
  }
  if (is.null(text)) {
    return(heartbeat_result(reason = "network_error"))
  }

  result <- parse_heartbeat_response(text)

  # Persist cache fields; read-only FS OK to fail silently.
  cfg$last_update_check <- Sys.time()
  cfg$update_available  <- result$update_available
  cfg$latest_version    <- result$latest_version
  # Per-module fields: only overwrite when we asked the server about that
  # module (i.e., a version was sent). Preserves prior cached state for
  # untouched modules. Matches Stata and Python policy.
  if (!is.null(autolabel_version)) {
    cfg$autolabel_update_available <- isTRUE(result$autolabel_update)
    cfg$autolabel_latest_version   <- result$autolabel_latest %||% ""
  }
  if (!is.null(datamirror_version)) {
    cfg$datamirror_update_available <- isTRUE(result$datamirror_update)
    cfg$datamirror_latest_version   <- result$datamirror_latest %||% ""
  }
  tryCatch(config_save(cfg, dir_), error = function(e) invisible(NULL))

  result
}


installed_version <- function(pkg) {
  tryCatch(
    as.character(utils::packageVersion(pkg)),
    error = function(e) NULL
  )
}


check_package <- function(version, directory = NULL) {
  dir_ <- registream_config_dir(directory)
  cfg  <- config_load(dir_)

  if (!isTRUE(cfg$internet_access)) {
    return(heartbeat_result(reason = "internet_disabled"))
  }

  # Expire the cache so send_heartbeat actually fetches.
  cfg$last_update_check <- as.POSIXct("1970-01-01", tz = "UTC")
  tryCatch(config_save(cfg, dir_), error = function(e) invisible(NULL))

  send_heartbeat(
    version,
    command            = "registream update",
    directory          = dir_,
    autolabel_version  = installed_version("autolabel"),
    datamirror_version = installed_version("datamirror")
  )
}


compare_versions <- function(current, latest) {
  tryCatch(
    compare_version_tuples(parse_semver(latest), parse_semver(current)) > 0L,
    error = function(e) FALSE
  )
}


show_notification <- function(current_version,
                              result,
                              modules = c("registream", "autolabel", "datamirror")) {
  lines <- character(0)
  rule <- strrep("-", 60)

  if ("registream" %in% modules && isTRUE(result$update_available)) {
    lines <- c(
      lines,
      "",
      rule,
      "A new version of registream is available!",
      sprintf("  Current version:  %s", current_version),
      sprintf("  Latest version:   %s", result$latest_version),
      "",
      "To update, run: rs_update()",
      rule,
      ""
    )
  }

  if ("autolabel" %in% modules &&
      isTRUE(result$autolabel_update) &&
      nzchar(result$autolabel_latest %||% "")) {
    lines <- c(
      lines,
      "",
      rule,
      "A new version of autolabel is available!",
      sprintf("  Latest version:   %s", result$autolabel_latest),
      "",
      "To update, run: rs_update(pkg = 'autolabel')",
      rule,
      ""
    )
  }

  if ("datamirror" %in% modules &&
      isTRUE(result$datamirror_update) &&
      nzchar(result$datamirror_latest %||% "")) {
    lines <- c(
      lines,
      "",
      rule,
      "A new version of datamirror is available!",
      sprintf("  Latest version:   %s", result$datamirror_latest),
      "",
      "To update, run: rs_update(pkg = 'datamirror')",
      rule,
      ""
    )
  }

  paste(lines, collapse = "\n")
}


rs_update <- function(channel = c("cran", "registream"),
                      pkg = "registream") {
  channel <- match.arg(channel)
  repo <- switch(
    channel,
    cran       = "https://cloud.r-project.org/",
    registream = "https://registream.org/r/"
  )
  if (!interactive()) {
    cat(sprintf("Run interactively to install, or use:\n"))
    cat(sprintf("  install.packages(%s, repos = %s)\n",
                shQuote(pkg), shQuote(repo)))
    return(invisible(NULL))
  }
  ans <- utils::askYesNo(sprintf("Install latest %s from %s?", pkg, channel))
  if (isTRUE(ans)) {
    utils::install.packages(pkg, repos = repo)
  }
  invisible(NULL)
}


# ─── Internal helpers ────────────────────────────────────────────────────────

heartbeat_result <- function(update_available = FALSE,
                             latest_version = "",
                             autolabel_update = FALSE,
                             autolabel_latest = "",
                             datamirror_update = FALSE,
                             datamirror_latest = "",
                             reason = "success") {
  structure(
    list(
      update_available  = update_available,
      latest_version    = latest_version,
      autolabel_update  = autolabel_update,
      autolabel_latest  = autolabel_latest,
      datamirror_update = datamirror_update,
      datamirror_latest = datamirror_latest,
      reason            = reason
    ),
    class = "registream_heartbeat_result"
  )
}


build_heartbeat_url <- function(version,
                                command,
                                cfg,
                                directory,
                                autolabel_version,
                                datamirror_version) {
  params <- list(
    platform    = "r",
    registream  = version,
    format      = "stata"   # plain-text key=value response format
  )

  if (isTRUE(cfg$telemetry_enabled)) {
    params$user_id           <- compute_user_id(directory)
    params$command           <- command
    params$os                <- Sys.info()[["sysname"]]
    params$platform_version  <- as.character(getRversion())
    params$timestamp         <- format(
      Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    )
  }

  if (!is.null(autolabel_version)) {
    params$autolabel <- autolabel_version
  }
  if (!is.null(datamirror_version)) {
    params$datamirror <- datamirror_version
  }

  query <- urlencode_params(params)
  paste0(get_api_host(), HEARTBEAT_PATH, "?", query)
}


urlencode_params <- function(params) {
  pieces <- vapply(names(params), function(k) {
    v <- as.character(params[[k]])
    sprintf("%s=%s", utils::URLencode(k, reserved = TRUE),
            utils::URLencode(v, reserved = TRUE))
  }, character(1))
  paste(pieces, collapse = "&")
}


parse_heartbeat_response <- function(text) {
  result <- heartbeat_result()
  for (raw in strsplit(text, "\n", fixed = TRUE)[[1]]) {
    line <- trimws(raw)
    if (!nzchar(line)) next
    eq <- regexpr("=", line, fixed = TRUE)
    if (eq < 1L) next
    key <- trimws(substr(line, 1L, eq - 1L))
    val <- trimws(substr(line, eq + 1L, nchar(line)))

    if (key == "registream_update") {
      result$update_available <- tolower(val) == "true"
    } else if (key == "registream_latest") {
      result$latest_version <- val
    } else if (key == "autolabel_update") {
      result$autolabel_update <- tolower(val) == "true"
    } else if (key == "autolabel_latest") {
      result$autolabel_latest <- val
    } else if (key == "datamirror_update") {
      result$datamirror_update <- tolower(val) == "true"
    } else if (key == "datamirror_latest") {
      result$datamirror_latest <- val
    }
  }
  result
}


parse_semver <- function(s) {
  # Strip pre-release and build metadata: everything after '-' or '+'.
  s <- sub("[-+].*$", "", s)
  parts <- strsplit(s, ".", fixed = TRUE)[[1]]
  result <- suppressWarnings(as.integer(parts))
  if (any(is.na(result))) {
    stop("Invalid semver component", call. = FALSE)
  }
  result
}


compare_version_tuples <- function(a, b) {
  len <- max(length(a), length(b))
  length(a) <- len
  length(b) <- len
  a[is.na(a)] <- 0L
  b[is.na(b)] <- 0L
  diffs <- a - b
  nonzero <- diffs[diffs != 0L]
  if (length(nonzero) == 0L) return(0L)
  sign(nonzero[[1]])
}


# POST a JSON-encoded body. Returns the response body as a string on
# 2xx, raises on non-2xx (so send_heartbeat can catch and fall back to
# GET). Uses the same user-agent / timeout conventions as http_get_text.
http_post_json <- function(url, body, timeout_seconds = 10L) {
  handle <- curl::new_handle()
  curl::handle_setheaders(handle, "Content-Type" = "application/json")
  curl::handle_setopt(
    handle,
    timeout         = timeout_seconds,
    followlocation  = TRUE,
    useragent       = sprintf("registream-r/%s",
                              utils::packageVersion("registream")),
    customrequest   = "POST",
    postfields      = body
  )
  resp <- curl::curl_fetch_memory(url, handle = handle)
  if (resp$status_code < 200L || resp$status_code >= 300L) {
    stop(sprintf("HTTP %d", resp$status_code), call. = FALSE)
  }
  rawToChar(resp$content)
}


# Read usage_r.csv rows with `timestamp > since` (ISO 8601 UTC). Returns
# a data.frame; empty when the file is absent or no rows are pending.
read_pending_usage <- function(directory, since = NULL) {
  path <- file.path(directory, USAGE_FILENAME)
  if (!file.exists(path)) return(data.frame())

  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(lines) <= 1L) return(data.frame())

  header <- strsplit(lines[[1]], ";", fixed = TRUE)[[1]]
  rows <- lapply(lines[-1L], function(raw) {
    f <- strsplit(raw, ";", fixed = TRUE)[[1]]
    if (length(f) < length(header)) {
      f <- c(f, rep("", length(header) - length(f)))
    }
    stats::setNames(as.list(f[seq_along(header)]), header)
  })
  df <- do.call(rbind, lapply(rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
  if (is.null(df) || nrow(df) == 0L) return(data.frame())

  if (!is.null(since)) {
    since_iso <- format(as.POSIXct(since, tz = "UTC"),
                        "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    df <- df[df$timestamp > since_iso, , drop = FALSE]
  }
  rownames(df) <- NULL
  df
}


build_heartbeat_payload <- function(version, pending) {
  body_list <- list(
    format     = "stata",
    registream = version,
    usage      = unname(apply(pending, 1L, as.list))
  )
  jsonlite::toJSON(body_list, auto_unbox = TRUE, null = "null", na = "string")
}


http_get_text <- function(url, timeout_seconds = 10L) {
  handle <- curl::new_handle()
  curl::handle_setopt(
    handle,
    timeout         = timeout_seconds,
    followlocation  = TRUE,
    useragent       = sprintf("registream-r/%s",
                              utils::packageVersion("registream"))
  )
  resp <- curl::curl_fetch_memory(url, handle = handle)
  if (resp$status_code < 200L || resp$status_code >= 300L) {
    stop(sprintf("HTTP %d", resp$status_code), call. = FALSE)
  }
  rawToChar(resp$content)
}


# Binary-safe GET to disk. Used by autolabel's rs_update_datasets() to
# download bundle ZIPs. Follows redirects, raises on non-2xx, uses a
# longer timeout than heartbeat calls since bundles can be hundreds of
# MB. Writes directly to `dest_path` so we never hold the full payload
# in memory.
http_download_file <- function(url, dest_path, timeout_seconds = 60L) {
  handle <- curl::new_handle()
  curl::handle_setopt(
    handle,
    timeout         = timeout_seconds,
    followlocation  = TRUE,
    useragent       = sprintf("registream-r/%s",
                              utils::packageVersion("registream"))
  )
  dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
  resp <- curl::curl_download(url, destfile = dest_path, handle = handle,
                              mode = "wb", quiet = TRUE)
  invisible(resp)
}
