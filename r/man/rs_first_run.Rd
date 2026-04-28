\name{rs_first_run}
\alias{rs_first_run}
\title{Run the RegiStream First-Time Setup Wizard}
\usage{
rs_first_run(directory = NULL, force = FALSE)
}
\arguments{
  \item{directory}{Optional configuration directory. Defaults to
    \code{REGISTREAM_DIR} if set, otherwise
    \code{tools::R_user_dir("registream", "config")}.}
  \item{force}{If \code{TRUE}, re-run the wizard even if
    \code{first_run_completed} is already set. Defaults to \code{FALSE}.}
}
\description{
Interactive three-mode setup (Offline / Standard / Full) that records
the user's preferences in \code{config_r.toml}. Mirrors the Python and
Stata first-run wizards.
}
\details{
Resolution order:
\enumerate{
  \item If \code{force = FALSE} and \code{first_run_completed} is already
    \code{TRUE}, return the existing config unchanged.
  \item If the environment variable \code{REGISTREAM_AUTO_APPROVE=yes}
    is set (case-insensitive), the wizard silently picks \strong{Full Mode}
    (matching Python and Stata behaviour for batch/scripted use).
  \item In a non-interactive R session (\code{interactive() == FALSE})
    with no AUTO_APPROVE override, the wizard silently picks
    \strong{Offline Mode}. This is required for CRAN compliance:
    \code{R CMD check} runs non-interactively and must not emit prompts,
    make network calls, or write outside \code{R_user_dir}.
  \item Otherwise, the wizard prints the three-option welcome banner
    and reads a choice via \code{readline()}.
}

The three presets match Stata's \code{_rs_config.ado}:
\tabular{llll}{
  \strong{Mode} \tab \strong{telemetry} \tab \strong{internet} \tab \strong{auto-update} \cr
  Offline  \tab FALSE \tab FALSE \tab FALSE \cr
  Standard \tab FALSE \tab TRUE  \tab TRUE  \cr
  Full     \tab TRUE  \tab TRUE  \tab TRUE  \cr
}
All three set \code{usage_logging = TRUE} and \code{first_run_completed = TRUE}.
}
\value{
The resulting \code{registream_config} record, returned invisibly.
}
\examples{
\dontrun{
  rs_first_run()               # interactive wizard
  rs_first_run(force = TRUE)   # re-run even if first_run_completed is TRUE
}
}
\keyword{configuration}
