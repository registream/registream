# Cache directory resolution.
#
# Three-tier lookup, matching the Python/Stata clients' REGISTREAM_DIR
# convention while staying CRAN-compliant by default:
#
#   1. REGISTREAM_DIR environment variable (explicit override)
#   2. `cache_dir` field in config_r.toml (set via the first-run wizard
#      when the user opts into sharing with the Python/Stata clients)
#   3. tools::R_user_dir("registream", "cache"): CRAN-blessed default

cache_dir <- function() {
  env <- Sys.getenv("REGISTREAM_DIR", unset = "")
  if (nzchar(env)) {
    return(path.expand(env))
  }
  from_config <- config_cache_dir()
  if (!is.null(from_config) && nzchar(from_config)) {
    return(path.expand(from_config))
  }
  tools::R_user_dir("registream", which = "cache")
}

cache_path <- function(...) {
  file.path(cache_dir(), ...)
}

config_cache_dir <- function() {
  # Tier 2: read `cache_dir` from config_r.toml, if present. Must not
  # recurse back into cache_dir(). config_load() resolves the config
  # path independently via registream_config_dir(), which only consults
  # REGISTREAM_DIR and tools::R_user_dir("registream", "config").
  path <- tryCatch(config_path(), error = function(e) NULL)
  if (is.null(path) || !file.exists(path)) {
    return(NULL)
  }
  cfg <- tryCatch(config_load(), error = function(e) NULL)
  if (is.null(cfg)) {
    return(NULL)
  }
  value <- cfg$cache_dir
  if (is.null(value) || !nzchar(value)) {
    return(NULL)
  }
  value
}
