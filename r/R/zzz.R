.onAttach <- function(libname, pkgname) {
  v <- utils::packageVersion(pkgname)
  packageStartupMessage(
    sprintf("registream %s -- type `rs_info()` for configuration", v)
  )
}
