\name{rs_info}
\alias{rs_info}
\title{Display the Current RegiStream Configuration}
\usage{
rs_info(directory = NULL)
}
\arguments{
  \item{directory}{Optional configuration directory. Defaults to
    \code{REGISTREAM_DIR} if set, otherwise
    \code{tools::R_user_dir("registream", "config")}.}
}
\description{
Print a multi-line summary of the current RegiStream configuration
-- the configuration directory, the resolved cache directory, the
installed package version, and the four boolean preference flags.
Mirrors Stata's \code{registream info} and Python's
\code{registream.info()}.
}
\value{
The multi-line character vector that was printed, returned invisibly.
}
\keyword{configuration}
