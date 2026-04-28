# First-run interactive wizard -- mirrors registream/first_run.py.
#
# Three setup modes (Offline / Standard / Full) plus a cache-location
# choice. Idempotent -- skips if already completed.
#
# Environment-variable control:
#
#   REGISTREAM_AUTO_APPROVE=yes   -> silently pick Full Mode + R-only
#                                   cache (isolated from Stata/Python,
#                                   no surprise writes to ~/.registream/).
#                                   Used by tests and non-interactive
#                                   scripts that want the maximal feature
#                                   set without any prompt.
#
# In non-interactive R sessions (`interactive() == FALSE`) with no
# AUTO_APPROVE override, the wizard writes a **transient** Offline
# config to R_user_dir WITHOUT setting `first_run_completed = TRUE`.
# This is the CRAN-safe path: `R CMD check` runs in a non-interactive
# session and must not make network calls, must not write outside
# R_user_dir, and must not emit warnings. Offline Mode + R_user_dir
# cache satisfies all three. Leaving `first_run_completed = FALSE`
# means the next interactive session re-fires the wizard, preventing
# the lock-in where an accidental Rscript invocation silently commits
# the user to Offline + R_user_dir forever.
#
# Cross-client cache sharing (cache at ~/.registream/, shared with the
# Stata and Python clients) is *only* reached via an explicit interactive
# Y/N prompt. That prompt is the CRAN-sanctioned consent mechanism -- see
# the CRAN Repository Policy clause "Limited exceptions may be allowed
# in interactive sessions if the package obtains confirmation from the
# user." We never write to ~/.registream/ without that keystroke.


AUTO_APPROVE_ENV <- "REGISTREAM_AUTO_APPROVE"
FIRST_RUN_DEFAULT_CHOICE <- "3"  # Full Mode
SHARED_CACHE_PATH <- "~/.registream"


rs_first_run <- function(directory = NULL, force = FALSE) {
  existing <- config_load(directory)
  if (!force && isTRUE(existing$first_run_completed)) {
    return(invisible(existing))
  }

  auto <- tolower(Sys.getenv(AUTO_APPROVE_ENV, unset = ""))
  if (auto == "yes") {
    choice <- FIRST_RUN_DEFAULT_CHOICE
    cache_choice <- "2"  # Isolated R_user_dir cache: no silent ~/.registream/ writes in CI.
  } else if (!interactive()) {
    # Non-interactive first run: write a *transient* Offline config to
    # R_user_dir, but leave `first_run_completed = FALSE` so the next
    # interactive session still runs the wizard. Rationale:
    #
    # - We cannot prompt (no stdin). CRAN forbids network calls + $HOME
    #   writes in non-interactive sessions without prior consent.
    # - Writing the config is necessary so the rest of this session's
    #   telemetry stack (usage_log, send_heartbeat) sees
    #   internet_access=FALSE and makes zero network calls. Without
    #   this, the in-memory `config_defaults()` would leak Full Mode
    #   (telemetry ON) and `R CMD check --as-cran` would flag a
    #   network call.
    # - Not persisting `first_run_completed` avoids the lock-in where
    #   an accidental Rscript / CI invocation silently commits the
    #   user to Offline + R_user_dir forever. The next interactive
    #   session re-fires the wizard and the user gets to pick a real
    #   cache location (including the shared ~/.registream/ option).
    #
    # This mirrors Python's behavior: `registream-python`'s wizard is
    # never auto-triggered by autolabel-python, so a Python CI run
    # with no prior config just uses in-memory defaults and does not
    # persist anything. Our transient-write approach is strictly safer
    # than Python's because it writes Offline (no telemetry), whereas
    # Python's defaults are Full Mode (telemetry ON).
    cfg <- modify_defaults(
      usage_logging       = TRUE,
      telemetry_enabled   = FALSE,
      internet_access     = FALSE,
      auto_update_check   = FALSE,
      first_run_completed = FALSE  # transient, re-prompt next interactive session
    )
    config_save(cfg, directory)
    return(invisible(cfg))
  } else {
    print_first_run_welcome(directory)
    choice <- prompt_first_run_choice()
    cache_choice <- prompt_cache_location()
  }

  cfg <- config_for_choice(choice)
  save_dir <- directory
  if (cache_choice == "1") {
    cfg$cache_dir <- SHARED_CACHE_PATH
    # When the user opts into sharing, write config_r.toml to
    # ~/.registream/ too so all three clients' per-client config files
    # (config_stata.csv, config_python.toml, config_r.toml) live in one
    # folder. The explicit wizard keystroke is the CRAN-sanctioned
    # confirmation for this write. If a caller passed `directory`
    # (tests, non-default use), we respect that and don't override.
    if (is.null(directory)) {
      save_dir <- SHARED_CACHE_PATH
    }
  }
  config_save(cfg, save_dir)
  invisible(cfg)
}


config_for_choice <- function(choice) {
  if (choice == "1") {
    return(modify_defaults(
      usage_logging       = TRUE,
      telemetry_enabled   = FALSE,
      internet_access     = FALSE,
      auto_update_check   = FALSE,
      first_run_completed = TRUE
    ))
  }
  if (choice == "2") {
    return(modify_defaults(
      usage_logging       = TRUE,
      telemetry_enabled   = FALSE,
      internet_access     = TRUE,
      auto_update_check   = TRUE,
      first_run_completed = TRUE
    ))
  }
  if (choice == "3") {
    return(modify_defaults(
      usage_logging       = TRUE,
      telemetry_enabled   = TRUE,
      internet_access     = TRUE,
      auto_update_check   = TRUE,
      first_run_completed = TRUE
    ))
  }
  stop(sprintf(
    "Invalid choice: %s. Must be '1' (Offline), '2' (Standard), or '3' (Full).",
    shQuote(choice)
  ), call. = FALSE)
}


modify_defaults <- function(...) {
  cfg <- config_defaults()
  updates <- list(...)
  for (key in names(updates)) {
    cfg[[key]] <- updates[[key]]
  }
  cfg
}


prompt_first_run_choice <- function() {
  repeat {
    raw <- tryCatch(
      readline("Enter choice (1-3): "),
      error = function(e) stop(
        "First-run wizard aborted (EOF on stdin).", call. = FALSE
      )
    )
    raw <- tolower(trimws(raw))
    if (raw %in% c("1", "2", "3")) {
      return(raw)
    }
    if (raw %in% c("exit", "quit", "q")) {
      stop("First-run setup aborted by user.", call. = FALSE)
    }
    cat(sprintf("Invalid choice %s. Please enter 1, 2, or 3 (or 'q' to abort).\n",
                shQuote(raw)))
  }
}


# Second prompt: cache location. Default (option 1) is the shared
# ~/.registream/ directory used by the Stata and Python clients. This
# prompt, together with the user's keystroke, is the CRAN-sanctioned
# "confirmation from the user" that authorises a write to $HOME -- see
# CRAN Repository Policy: "Limited exceptions may be allowed in
# interactive sessions if the package obtains confirmation from the
# user."
prompt_cache_location <- function() {
  cache_r <- tools::R_user_dir("registream", which = "cache")
  cat("\n")
  cat("Where should RegiStream store its files (config, usage log,\n")
  cat("bundle cache, and update metadata)?\n")
  cat("\n")
  cat(sprintf("  1) %s   (recommended -- one folder shared across\n",
              SHARED_CACHE_PATH))
  cat("                     the Stata / Python / R clients)\n")
  cat(sprintf("  2) %s\n", cache_r))
  cat("                     (R-only, isolated from Stata / Python)\n")
  cat("\n")
  cat("Your choice applies to all current and future RegiStream files\n")
  cat("in that directory. You can change it later via config_set().\n")
  cat("\n")
  repeat {
    raw <- tryCatch(
      readline("Select cache location (1-2) [1]: "),
      error = function(e) stop(
        "First-run wizard aborted (EOF on stdin).", call. = FALSE
      )
    )
    raw <- tolower(trimws(raw))
    if (!nzchar(raw)) return("1")  # Enter = shared cache (recommended)
    if (raw %in% c("1", "2")) return(raw)
    if (raw %in% c("exit", "quit", "q")) {
      stop("First-run setup aborted by user.", call. = FALSE)
    }
    cat(sprintf("Invalid choice %s. Please enter 1 or 2 (or 'q' to abort).\n",
                shQuote(raw)))
  }
}


print_first_run_welcome <- function(directory) {
  dir_ <- registream_config_dir(directory)
  rule <- strrep("-", 60)
  message <- paste(
    "",
    rule,
    "RegiStream - First-Time Setup",
    rule,
    "",
    "Welcome to RegiStream! You will be asked two questions:",
    "",
    "  1. Setup mode (Offline / Standard / Full)",
    "  2. Cache location (shared with Stata / Python, or R-only)",
    "",
    sprintf("Configuration directory: %s", dir_),
    "",
    "Setup Options:",
    "",
    "  1) Offline Mode",
    "     * No internet connections",
    "     * Manual metadata management",
    "     * Local usage logging only (stays on your machine)",
    "",
    "  2) Standard Mode",
    "     * Automatic metadata downloads from registream.org",
    "     * Automatic update checks (daily)",
    "     * Local usage logging only (stays on your machine)",
    "     * No online telemetry",
    "",
    "  3) Full Mode (Help Improve RegiStream)",
    "     * Everything in Standard Mode, plus:",
    "     * Online telemetry: anonymized usage data to help improve",
    "       RegiStream (commands run, version, OS - no dataset content)",
    "",
    "Note: You can change these settings later via:",
    "  registream::config_set('telemetry_enabled', FALSE)",
    "",
    rule,
    "",
    sep = "\n"
  )
  cat(message)
}
