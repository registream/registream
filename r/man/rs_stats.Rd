\name{rs_stats}
\alias{rs_stats}
\alias{print.registream_usage_stats}
\title{Summarize Local RegiStream Usage}
\usage{
rs_stats(directory = NULL, all_users = FALSE)
}
\arguments{
  \item{directory}{Optional configuration directory. Defaults to
    \code{REGISTREAM_DIR} if set, otherwise
    \code{tools::R_user_dir("registream", "config")}.}
  \item{all_users}{If \code{TRUE}, aggregate across every \code{user_id}
    found in \code{usage_r.csv}. Defaults to \code{FALSE} (this user only).}
}
\description{
Read \code{usage_r.csv} and return a \code{registream_usage_stats}
record with the current anonymous user id, total command count, number
of distinct users in the file, and the first/last use timestamps.
Mirrors Stata \code{registream stats} and Python
\code{registream.usage.stats()}.
}
\value{
A \code{registream_usage_stats} list with fields \code{user_id},
\code{total_calls}, \code{unique_users}, \code{first_use}, and
\code{last_use}. The object has a custom \code{print} method; callers
that want structured access can subscript the list directly.
}
\examples{
\dontrun{
  rs_stats()
  rs_stats(all_users = TRUE)
}
}
\keyword{usage}
