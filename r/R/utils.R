# Shared utility helpers: API host resolution and filename escaping.
#
# Mirrors registream/utils.py. Both the Python and R clients must produce
# the same escape_ascii() output for the same input or the shared metadata
# cache breaks.

get_api_host <- function() {
  host <- Sys.getenv("REGISTREAM_API_HOST", unset = "")
  if (nzchar(host)) {
    return(host)
  }
  "https://registream.org"
}

# Q-code escape table. Must match `_utils_escape_ascii` in
# stata/src/_rs_utils.ado and registream/utils.py exactly. Any divergence
# breaks shared metadata cache compatibility across clients.
ASCII_ESCAPES <- list(
  c(".", "q46"),
  c("*", "q42"),
  c("/", "q47"),
  c("&", "q38"),
  c("-", "q45"),
  c("_", "q95"),
  c("[", "q91"),
  c("]", "q93"),
  c("{", "q123"),
  c("}", "q125"),
  c(" ", "q32")
)

escape_ascii <- function(s) {
  for (pair in ASCII_ESCAPES) {
    s <- gsub(pair[[1]], pair[[2]], s, fixed = TRUE)
  }
  s
}
