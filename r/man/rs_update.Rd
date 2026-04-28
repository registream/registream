\name{rs_update}
\alias{rs_update}
\title{Install the Latest RegiStream Package}
\usage{
rs_update(channel = c("cran", "registream"), pkg = "registream")
}
\arguments{
  \item{channel}{Which repository to install from. \code{"cran"} (default)
    uses \code{https://cloud.r-project.org/}; \code{"registream"} uses
    \code{https://registream.org/r/} for faster release cadence between
    CRAN updates.}
  \item{pkg}{Package name to install. Defaults to \code{"registream"};
    pass \code{"autolabel"} to update the labelling client.}
}
\description{
Install the latest version of \pkg{registream} or \pkg{autolabel} from
CRAN or from the \code{registream.org} drat repository. Interactive
only -- prints the \code{install.packages()} command and optionally
runs it after an explicit y/N confirmation. In non-interactive sessions
the command is printed and nothing is installed, which is required for
CRAN compliance (no package self-modification).
}
\value{
\code{NULL}, invisibly.
}
\examples{
\dontrun{
  rs_update()                        # install latest from CRAN
  rs_update(channel = "registream")  # install latest from registream.org drat
  rs_update(pkg = "autolabel")       # update the labelling client
}
}
\keyword{configuration}
