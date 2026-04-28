\name{rs_cite}
\alias{rs_cite}
\alias{rs_cite_bibtex}
\title{Citation Output for the registream Core Package}
\description{
Produce the citation information for \pkg{registream}. \code{rs_cite()}
returns the full Stata-style citation block (horizontal rules,
"To cite RegiStream..." lead-in, the versioned APA line, and an
"Installed datasets:" section with the catalog URL for each cached
domain). The output matches \code{registream cite} in Stata and
\code{python -m registream cite} in Python byte-for-byte, so users see
the same thing across clients.

\code{rs_cite_bibtex()} returns the BibTeX entry for the installed
version.

Citation strings are generated from the single-source
\code{registream/citations.yaml} by
\code{registream/tools/render_citations.py} and stored in
\code{R/citation_data.R}. Do not hand-edit that file -- regenerate
from YAML.
}
\usage{
rs_cite(versioned = TRUE, directory = NULL)

rs_cite_bibtex(versioned = TRUE)
}
\arguments{
\item{versioned}{If \code{TRUE} (default), include the installed
  package version in the APA line. If \code{FALSE}, emit the short /
  version-free form.}
\item{directory}{Optional configuration directory used to locate
  \code{autolabel/datasets.csv} for the "Installed datasets" section.
  Defaults to the resolved cache directory.}
}
\value{
A single multi-line character string. \code{rs_cite()} returns the
full citation block (print with \code{cat()} for readable output;
the raw string includes newline separators). \code{rs_cite_bibtex()}
returns a \code{@software\{...\}} BibTeX entry.
}
\examples{
\dontrun{
cat(rs_cite())
cat(rs_cite_bibtex())
}
}
\seealso{
\code{\link{rs_info}}, autolabel's \code{cite()} wrapper,
\code{\link[utils]{citation}} (generic R citation lookup, served
by \code{inst/CITATION}).
}
\keyword{utilities}
