# Display the current RegiStream configuration. Mirrors Python info().
#
# Returns a multi-line character vector that the caller can print. Mirroring
# Python, the content and the display are separated so tests can capture
# the lines without staring at stdout.

rs_info <- function(directory = NULL) {
  lines <- info_lines(directory)
  cat(lines, sep = "\n")
  invisible(lines)
}

info_lines <- function(directory = NULL) {
  dir_ <- registream_config_dir(directory)
  cfg  <- config_load(directory)

  ver <- tryCatch(
    as.character(utils::packageVersion("registream")),
    error = function(e) "unknown"
  )

  bool_str <- function(b) tolower(as.character(isTRUE(b)))

  rule <- strrep("-", 60)

  # Citation line is sourced from the generated _citation_data.R constants
  # (which come from registream/citations.yaml via render_citations.py).
  # Never hand-edit here; drift caught us once when the title + year
  # were stale. See design/citation.md.
  c(
    "",
    rule,
    "RegiStream Configuration",
    rule,
    sprintf("Directory:        %s", dir_),
    sprintf("Config file:      %s", config_path(directory)),
    "",
    "Package:",
    sprintf("  version:         %s", ver),
    "",
    "Settings:",
    sprintf("  usage_logging:       %s", bool_str(cfg$usage_logging)),
    sprintf("  telemetry_enabled:   %s", bool_str(cfg$telemetry_enabled)),
    sprintf("  internet_access:     %s", bool_str(cfg$internet_access)),
    sprintf("  auto_update_check:   %s", bool_str(cfg$auto_update_check)),
    rule,
    "",
    "Citation:",
    paste0("  ", .CITATION_APA),
    ""
  )
}
