# RegiStream citation text -- parity with Stata `registream cite` and
# Python `registream.citation.cite`. Data sourced from the generated
# `_citation_data.R` (which lives next to this file and is produced from
# the ecosystem-wide `citations.yaml` by
# `registream/tools/render_citations.py write-r`).
#
# rs_cite() returns the full Stata-style block (header rules, "To cite
# RegiStream..." lead-in, the versioned APA line, and an "Installed
# datasets:" section read from <registream_dir>/autolabel/datasets.csv).
# rs_cite_bibtex() returns the BibTeX entry. Both always reflect the
# installed `registream` package version via utils::packageVersion().

.CITATION_HLINE <- strrep("-", 60)


#' @export
rs_cite <- function(versioned = TRUE, directory = NULL) {
  apa <- if (isTRUE(versioned)) {
    sprintf(.CITATION_APA_VERSIONED_TEMPLATE, .installed_registream_version())
  } else {
    .CITATION_APA
  }

  datasets_lines <- .format_installed_datasets(directory)

  lines <- c(
    "",
    .CITATION_HLINE,
    "Citation",
    .CITATION_HLINE,
    "",
    "To cite RegiStream in publications, please use:",
    "",
    paste0("  ", apa),
    "",
    "Installed datasets:",
    "",
    datasets_lines,
    "",
    .CITATION_HLINE,
    ""
  )
  paste(lines, collapse = "\n")
}


#' @export
rs_cite_bibtex <- function(versioned = TRUE) {
  if (!isTRUE(versioned)) return(.CITATION_BIBTEX_PLAIN)
  gsub("{{VERSION}}", .installed_registream_version(),
       .CITATION_BIBTEX_VERSIONED_TEMPLATE, fixed = TRUE)
}


.installed_registream_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("registream")),
    error = function(e) "X.Y.Z"
  )
}


# Read <registream_dir>/autolabel/datasets.csv and return one bullet line
# per unique (domain, version) pair installed. The CSV has one row per
# cached file (variables/values/scope/... * language), so we dedup up to
# the (domain, version) level the user actually cares about. Each line
# ends with the catalog URL for that domain so users can look up provider
# details, source attribution, and version history.
#
# Returns "  (none installed yet)" on any read failure or empty registry.
# We avoid a runtime dependency on the autolabel package and just build
# the CSV path the same way Stata does.
.format_installed_datasets <- function(directory) {
  csv_path <- .datasets_csv_path(directory)
  if (is.null(csv_path) || !file.exists(csv_path)) {
    return("  (none installed yet)")
  }

  rows <- tryCatch(
    utils::read.table(
      csv_path,
      header = TRUE,
      sep = ";",
      stringsAsFactors = FALSE,
      fill = TRUE,
      na.strings = "",
      colClasses = "character",
      comment.char = ""
    ),
    error = function(e) NULL
  )
  if (is.null(rows) || nrow(rows) == 0) {
    return("  (none installed yet)")
  }

  # Columns: dataset_key(1), domain(2), type(3), lang(4), version(5), ...
  domains <- trimws(as.character(rows[[2]]))
  versions <- if (ncol(rows) >= 5) trimws(as.character(rows[[5]])) else character(nrow(rows))
  keep <- nzchar(domains) & nzchar(versions)
  if (!any(keep)) {
    return("  (none installed yet)")
  }

  domains_kept <- domains[keep]
  versions_kept <- versions[keep]
  uniq <- !duplicated(paste(domains_kept, versions_kept, sep = "|"))
  sprintf(
    "  \u2022 %s v%s \u2014 https://registream.org/catalog/%s",
    domains_kept[uniq], versions_kept[uniq], domains_kept[uniq]
  )
}


.datasets_csv_path <- function(directory) {
  base <- if (is.null(directory)) {
    tryCatch(cache_dir(), error = function(e) NULL)
  } else {
    path.expand(directory)
  }
  if (is.null(base) || !nzchar(base)) return(NULL)
  file.path(base, "autolabel", "datasets.csv")
}
