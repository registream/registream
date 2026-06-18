"""Bundle cache reader for autolabel schema v2.

The cache lives at ``~/.registream/autolabel/{domain}/`` with one file
per (type, lang, ext) under that subdirectory::

    manifest_{lang}.csv
    variables_{lang}.{dta,csv}
    value_labels_{lang}.{dta,csv}
    scope_{lang}.{dta,csv}
    release_sets_{lang}.{dta,csv}

The previous layout (flat files named ``{domain}_{type}_{lang}.{ext}``
directly under ``~/.registream/autolabel/``) is migrated in-place by
:func:`migrate_legacy_cache`.

Reads DTA via ``pyreadstat`` with CSV fallback. Validates against
:mod:`registream.schema`.
"""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

from registream.dirs import get_registream_dir
from registream.schema import (
    FileType,
    Manifest,
    SchemaError,
    validate_manifest,
    validate_schema,
)

__all__ = [
    "AUTOLABEL_SUBDIR",
    "FileType",
    "LabelBundle",
    "cache_dir",
    "cache_filename",
    "cache_path",
    "domain_cache_dir",
    "load_bundle",
    "load_metadata",
    "migrate_legacy_cache",
]


AUTOLABEL_SUBDIR = "autolabel"

_FILENAME_INFIX: dict[str, str] = {
    "variables": "variables",
    "values": "value_labels",
    "scope": "scope",
    "release_sets": "release_sets",
    "manifest": "manifest",
}


@dataclass
class LabelBundle:
    """A loaded and validated autolabel bundle for one (domain, lang).

    ``core_only=True`` indicates that only the required files
    (``variables`` + ``value_labels``) were present; the optional
    augmentation files (``manifest``, ``scope``, ``release_sets``) were
    absent. In that mode :attr:`manifest` is a synthetic placeholder
    with ``scope_depth=0`` and empty level lists, and :attr:`scope` and
    :attr:`release_sets` are ``None``. Scope/release filtering is
    unavailable in core-only mode; callers must degrade gracefully.
    """

    domain: str
    lang: str
    manifest: Manifest
    variables: pd.DataFrame
    value_labels: pd.DataFrame
    scope: pd.DataFrame | None
    release_sets: pd.DataFrame | None
    core_only: bool


def cache_dir(directory: Path | str | None = None) -> Path:
    """Return ``~/.registream/autolabel/`` (or override)."""
    base = get_registream_dir() if directory is None else Path(directory).expanduser()
    return base / AUTOLABEL_SUBDIR


def domain_cache_dir(domain: str, directory: Path | str | None = None) -> Path:
    """Return the per-domain cache subdirectory."""
    return cache_dir(directory) / domain


def cache_filename(file_type: FileType, lang: str, *, ext: str = "dta") -> str:
    """Return the cache filename (without the domain subdirectory prefix).

    The domain is encoded by the containing directory, not the filename
    so for a given (domain, file_type, lang, ext) the full path is
    ``cache_dir(directory) / domain / cache_filename(file_type, lang, ext=ext)``.
    """
    if file_type not in _FILENAME_INFIX:
        raise ValueError(
            f"Invalid file_type: {file_type!r}. Must be one of "
            f"{sorted(_FILENAME_INFIX)}."
        )
    return f"{_FILENAME_INFIX[file_type]}_{lang}.{ext}"


def cache_path(
    domain: str,
    file_type: FileType,
    lang: str,
    *,
    ext: str = "dta",
    directory: Path | str | None = None,
) -> Path:
    """Return the absolute path to a cache file (no I/O)."""
    return domain_cache_dir(domain, directory) / cache_filename(file_type, lang, ext=ext)


def migrate_legacy_cache(directory: Path | str | None = None) -> int:
    """Move legacy flat-layout cache files into per-domain subdirectories.

    Legacy layout::

        ~/.registream/autolabel/scb_variables_eng.dta

    Current layout::

        ~/.registream/autolabel/scb/variables_eng.dta

    Idempotent: if a target file already exists (current-layout), the
    legacy flat file is removed without overwriting. Returns the count
    of files moved.
    """
    base = cache_dir(directory)
    if not base.exists():
        return 0

    moved = 0
    for src in list(base.glob("*.*")):
        if not src.is_file():
            continue
        if src.name in {"datasets.csv", ".salt"} or src.name.startswith("."):
            continue
        stem = src.stem  # e.g. scb_variables_eng
        parts = stem.split("_")
        if len(parts) < 3:
            continue
        domain = parts[0]
        rest = "_".join(parts[1:])
        infix_match: str | None = None
        lang: str | None = None
        for infix in _FILENAME_INFIX.values():
            if rest.startswith(infix + "_"):
                infix_match = infix
                lang = rest[len(infix) + 1 :]
                break
        if infix_match is None or not lang:
            continue
        dst = base / domain / f"{infix_match}_{lang}{src.suffix}"
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists():
            src.unlink()
        else:
            shutil.move(str(src), str(dst))
            moved += 1
    return moved


def load_bundle(
    domain: str,
    lang: str,
    *,
    directory: Path | str | None = None,
) -> LabelBundle:
    """Load the 5-file bundle from the cache and return a :class:`LabelBundle`.

    Order of operations:

    1. Migrate any legacy flat-layout files into the per-domain subdir
       (idempotent, cheap).
    2. Load and validate ``manifest_{lang}.csv`` if present.
    3. Load and validate ``variables`` and ``value_labels`` (required).
    4. Load and validate ``scope`` and ``release_sets`` if present.

    Raises :class:`FileNotFoundError` when required files are missing,
    and :class:`SchemaError` / :class:`SchemaVersionError` when
    validation fails.
    """
    migrate_legacy_cache(directory)

    ddir = domain_cache_dir(domain, directory)

    manifest_path = ddir / cache_filename("manifest", lang, ext="csv")
    manifest: Manifest | None = None
    if manifest_path.exists():
        manifest = validate_manifest(_read_csv(manifest_path))

    variables = _read_typed(domain, "variables", lang, directory, required=True)
    validate_schema(variables, "variables")

    value_labels = _read_typed(domain, "values", lang, directory, required=True)
    validate_schema(value_labels, "values")

    scope_df: pd.DataFrame | None = None
    release_sets_df: pd.DataFrame | None = None
    core_only = manifest is None

    if manifest is not None:
        scope_df = _read_typed(domain, "scope", lang, directory, required=False)
        if scope_df is not None:
            validate_schema(scope_df, "scope", scope_depth=manifest.scope_depth)
        release_sets_df = _read_typed(
            domain, "release_sets", lang, directory, required=False
        )
        if release_sets_df is not None:
            validate_schema(release_sets_df, "release_sets")
        if scope_df is None or release_sets_df is None:
            core_only = True

    if manifest is None:
        manifest = _synth_core_only_manifest(domain, lang)

    return LabelBundle(
        domain=domain,
        lang=lang,
        manifest=manifest,
        variables=variables,
        value_labels=value_labels,
        scope=scope_df,
        release_sets=release_sets_df,
        core_only=core_only,
    )


def load_metadata(
    domain: str,
    file_type: FileType,
    lang: str,
    *,
    directory: Path | str | None = None,
) -> pd.DataFrame:
    """Load one file type from the cache without loading the whole bundle.

    Resolution order: DTA then CSV. Validation is applied per-file (no
    cross-file consistency check; use :func:`load_bundle` for that).
    """
    df = _read_typed(domain, file_type, lang, directory, required=True)
    if file_type == "manifest":
        validate_manifest(df)
    else:
        validate_schema(df, file_type)
    return df


def _read_typed(
    domain: str,
    file_type: FileType,
    lang: str,
    directory: Path | str | None,
    *,
    required: bool,
) -> pd.DataFrame | None:
    if file_type == "manifest":
        path = cache_path(domain, "manifest", lang, ext="csv", directory=directory)
        if not path.exists():
            if required:
                raise _missing(domain, lang, path)
            return None
        return _read_csv(path)

    dta = cache_path(domain, file_type, lang, ext="dta", directory=directory)
    csv = cache_path(domain, file_type, lang, ext="csv", directory=directory)
    if dta.exists():
        return _read_dta(dta)
    if csv.exists():
        return _read_csv(csv)
    if required:
        raise _missing(domain, lang, dta, csv)
    return None


def _missing(domain: str, lang: str, *paths: Path) -> FileNotFoundError:
    joined = "\n  ".join(str(p) for p in paths)
    return FileNotFoundError(
        f"No cached autolabel file found for domain={domain!r}, lang={lang!r}.\n"
        f"Looked for:\n  {joined}\n\n"
        f'To populate the cache, run: update_datasets("{domain}", "{lang}")'
    )


def _synth_core_only_manifest(domain: str, lang: str) -> Manifest:
    """Return a placeholder manifest for core-only bundles."""
    from registream.schema import SCHEMA_VERSION

    return Manifest(
        domain=domain,
        schema_version=SCHEMA_VERSION,
        publisher="",
        bundle_release_date="",
        languages=[lang],
        scope_depth=0,
        level_names=[],
        level_titles=[],
        extra={},
    )


def _read_dta(path: Path) -> pd.DataFrame:
    import pyreadstat

    df, _meta = pyreadstat.read_dta(str(path))
    return df


def _read_csv(path: Path) -> pd.DataFrame:
    # CSV convention from docs/schema.md §CSV conventions: UTF-8,
    # semicolon-delimited (manifest + all data files).
    #
    # Fallback: a comma-delimited file (e.g. a cache written by an older
    # Stata client before the ``delimiter(";")`` fix) read as semicolon
    # collapses to a single fused column, after which the schema check
    # reports the first required column as missing although it is present.
    # Every v3 metadata file has at least two required columns, so a single
    # column unambiguously means the wrong delimiter: re-read as comma. The
    # header decides the count, so embedded ``;`` inside quoted fields is
    # irrelevant.
    df = pd.read_csv(path, encoding="utf-8", sep=";")
    if df.shape[1] <= 1:
        df = pd.read_csv(path, encoding="utf-8", sep=",")
    return df
