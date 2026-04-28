\name{registream-internal}
\alias{parse_value_labels_stata}
\alias{load_metadata}
\alias{load_bundle}
\alias{load_manifest}
\alias{load_scope}
\alias{load_release_sets}
\alias{migrate_legacy_cache}
\alias{synth_core_only_manifest}
\alias{rs_manifest}
\alias{rs_bundle}
\alias{validate_manifest}
\alias{validate_scope}
\alias{validate_release_sets}
\alias{validate_variables}
\alias{validate_value_labels}
\alias{validate_schema}
\alias{cache_dir}
\alias{cache_filename}
\alias{autolabel_cache_dir}
\alias{autolabel_cache_path}
\alias{autolabel_bundle_dir}
\alias{bundle_filename}
\alias{bundle_path}
\alias{config_defaults}
\alias{config_path}
\alias{config_init}
\alias{config_load}
\alias{config_save}
\alias{config_get}
\alias{config_set}
\alias{get_api_host}
\alias{escape_ascii}
\alias{stata_clock_to_posix}
\alias{posix_to_stata_clock}
\alias{compute_user_id}
\alias{usage_log}
\alias{usage_init}
\alias{usage_path}
\alias{compare_versions}
\alias{send_heartbeat}
\alias{check_package}
\alias{show_notification}
\alias{check_integrity}
\alias{http_get_text}
\alias{http_post_json}
\alias{http_download_file}
\alias{read_pending_usage}
\alias{build_heartbeat_payload}
\title{Internal RegiStream Helpers (Cross-Package API)}
\description{
These functions form the internal API that sibling packages in the
RegiStream ecosystem (\pkg{autolabel}, \pkg{datamirror}) call. They are
exported from the namespace so cross-package use does not require
\code{:::}, but they are not part of the user-facing API and may change
between releases without deprecation. End users should rely on the
\code{rs_*} wrappers instead.
}
\details{
\strong{v3 bundle loaders (schema_version = "2.0", 5-file layout):}
\itemize{
  \item \code{load_bundle(domain, lang, directory)} reads
    \code{manifest_\{lang\}.csv}, \code{variables_\{lang\}.dta},
    \code{value_labels_\{lang\}.dta}, \code{scope_\{lang\}.dta}, and
    \code{release_sets_\{lang\}.dta} from the per-domain cache layout
    and returns an \code{rs_bundle} S3 list. Triggers
    \code{migrate_legacy_cache()} on first call so pre-v3 flat-layout
    files are moved into the per-domain subdirectory in place.
  \item \code{load_manifest(domain, lang, directory)},
    \code{load_scope(domain, lang, scope_depth, directory)},
    \code{load_release_sets(domain, lang, directory)} read individual
    bundle files when callers do not need the full bundle.
  \item \code{load_metadata(domain, file_type, lang, directory)} reads
    a single bundle DTA / CSV file (DTA primary, semicolon-CSV
    fallback) and returns a plain data frame.
  \item \code{migrate_legacy_cache(directory)} walks any pre-v3
    flat-layout files (\code{\{domain\}_\{type\}_\{lang\}.\{ext\}})
    into the per-domain subdirectory
    (\code{\{domain\}/\{type\}_\{lang\}.\{ext\}}). Idempotent.
  \item \code{synth_core_only_manifest(domain, lang)} returns a
    placeholder \code{rs_manifest} with \code{scope_depth = 0} for
    bundles that ship without a manifest CSV.
  \item \code{rs_manifest(...)} / \code{rs_bundle(...)} are the S3
    constructors with custom \code{print} methods.
}

\strong{Schema validators:}
\itemize{
  \item \code{parse_value_labels_stata(s, type)} parses a Stata-format
    value-label string (e.g. \code{'"1" "Male" "2" "Female"'}) into a
    named vector with names = labels and values = codes.
  \item \code{validate_manifest(df)} parses the manifest data frame
    and returns an \code{rs_manifest}; raises \code{rs_error_schema}
    on validation failure.
  \item \code{validate_scope(df, scope_depth)} confirms the scope
    file carries \code{scope_level_1..N} columns matching the
    declared \code{scope_depth}.
  \item \code{validate_release_sets(df)} confirms the required
    \code{release_set_id} / \code{scope_id} columns are present.
  \item \code{validate_variables(df)} / \code{validate_value_labels(df)}
    confirm the v3 column contracts on the variables and value-labels
    files respectively.
  \item \code{validate_schema(df, file_type, scope_depth)} dispatches
    to the right validator for \code{file_type} (one of
    \code{"manifest"}, \code{"variables"}, \code{"values"},
    \code{"scope"}, \code{"release_sets"}).
}

\strong{Cache directory helpers:}
\itemize{
  \item \code{cache_dir()} returns the base RegiStream cache directory
    (\code{REGISTREAM_DIR} env var, then the \code{cache_dir} field in
    \code{config_r.toml}, then
    \code{tools::R_user_dir("registream", "cache")}).
  \item \code{autolabel_cache_dir(directory)} returns
    \code{<cache_dir>/autolabel} -- the subdirectory all autolabel
    files live under.
  \item \code{autolabel_bundle_dir(domain, directory)} returns
    \code{<cache_dir>/autolabel/<domain>} -- the per-domain bundle
    subdirectory.
  \item \code{bundle_filename(file_type, lang, ext)} and
    \code{bundle_path(domain, file_type, lang, ext, directory)} are
    the v3 path helpers (per-domain layout).
  \item \code{cache_filename(domain, file_type, lang, ext)} and
    \code{autolabel_cache_path(domain, file_type, lang, ext, directory)}
    are the legacy flat-layout helpers, kept so the migration helper
    can reach pre-v3 files before moving them.
  \item \code{check_integrity(domain, file_type, lang, file_path, directory)}
    validates the file size against the stored value in
    \code{datasets.csv}. Raises an \code{rs_error_integrity}
    condition on mismatch. Called automatically by
    \code{load_metadata()}.
}

\strong{Configuration helpers:}
\itemize{
  \item \code{config_defaults()} returns a \code{registream_config}
    record populated with Full-Mode defaults (same presets as Python's
    \code{Config()}).
  \item \code{config_path(directory)} returns the absolute path to
    \code{config_r.toml} inside the resolved config directory (env var
    \code{REGISTREAM_DIR} then
    \code{tools::R_user_dir("registream", "config")}).
  \item \code{config_init(directory)} creates the config file with
    default values if missing; otherwise returns the existing config.
    Fails gracefully on a read-only filesystem.
  \item \code{config_load(directory)} reads the config from disk and
    returns a \code{registream_config} record. Unknown TOML keys are
    silently ignored (forward compatibility).
  \item \code{config_save(cfg, directory)} writes a
    \code{registream_config} record to disk as flat TOML.
  \item \code{config_get(key, directory)} / \code{config_set(key, value, directory)}
    read or update a single field. Raises an error on unknown keys.
}

\strong{Shared utilities:}
\itemize{
  \item \code{get_api_host()} returns the RegiStream API host URL,
    honoring the \code{REGISTREAM_API_HOST} environment variable.
  \item \code{escape_ascii(s)} replaces a fixed set of special characters
    with q-code escapes so \code{s} is safe for use in shared filenames.
    Round-trips with Python \code{registream.utils.escape_ascii} and
    Stata \code{_rs_utils escape_ascii}.
  \item \code{stata_clock_to_posix(ms)} / \code{posix_to_stata_clock(t)}
    convert between POSIXct and Stata clock (milliseconds since
    1960-01-01 UTC). Used for cross-client \code{datasets.csv}
    compatibility.
}

\strong{Usage logging:}
\itemize{
  \item \code{compute_user_id(directory)} returns the 16-character
    SHA-256 hash of \code{username + hostname + salt}. The salt file
    is shared with the Python and Stata clients when the three files
    co-locate in \code{REGISTREAM_DIR}.
  \item \code{usage_log(command, module, module_version, core_version, directory)}
    appends a row to \code{usage_r.csv} (9-col schema matching
    Stata/Python). No-op when \code{usage_logging} is \code{FALSE}.
  \item \code{usage_init(directory)} ensures the salt file and the
    CSV header exist; rotates a stale 7-col header to
    \code{usage_r.csv.old} on first call after upgrade.
  \item \code{usage_path(directory)} returns the full path to
    \code{usage_r.csv}.
  \item \code{read_pending_usage(directory, since)} returns the
    usage_r.csv rows newer than \code{since} (used by the POST batch
    heartbeat path).
}

\strong{HTTP helpers:}
\itemize{
  \item \code{http_get_text(url, timeout_seconds)} performs a GET via
    \code{curl::curl_fetch_memory()} and returns the response body as
    a character string. Raises on non-2xx.
  \item \code{http_post_json(url, body, timeout_seconds)} performs a
    POST with a JSON body. Used by the v3 batch heartbeat path.
  \item \code{http_download_file(url, dest_path, timeout_seconds)}
    streams a GET response directly to disk via
    \code{curl::curl_download()}. Used by \code{rs_update_datasets}
    for bundle ZIP downloads.
}

\strong{Heartbeat and update check:}
\itemize{
  \item \code{compare_versions(current, latest)} returns \code{TRUE} if
    \code{latest} is semver-greater than \code{current}, stripping any
    pre-release or build metadata.
  \item \code{send_heartbeat(version, command, directory, ...)} is the
    main network entry point. Honors \code{internet_access},
    \code{auto_update_check}, and the 24-hour \code{last_update_check}
    cache. Issues a POST batch when usage rows have accumulated since
    the last heartbeat; falls back to GET on any POST error.
  \item \code{build_heartbeat_payload(version, pending)} constructs
    the JSON body \code{\{format, registream, usage\}} consumed by the
    POST path.
  \item \code{check_package(version, directory)} expires the cache and
    forces an immediate heartbeat -- the user-initiated "check for
    updates now" command.
  \item \code{show_notification(current_version, result)} formats the
    update banner from a heartbeat result. Returns the string; caller
    prints.
}
}
\keyword{internal}
