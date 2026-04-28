"""Schema validation for autolabel bundle files (schema v2.0, 5-file layout).

Mirrors ``autolabel/stata/src/_al_validate_schema.ado``. A conformant
bundle ships five CSV files per (domain, lang): manifest, scope,
variables, value_labels, release_sets (see
``autolabel/docs/schema.md``).

This module validates per-file column contracts and parses the manifest
into a :class:`Manifest` value. The ``schema_version`` must be exactly
``"2.0"``; there is no back-compat path for earlier iterations.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

import pandas as pd

__all__ = [
    "SCHEMA_VERSION",
    "FileType",
    "Manifest",
    "SchemaError",
    "SchemaVersionError",
    "VARIABLES_REQUIRED_COLUMNS",
    "VALUE_LABELS_REQUIRED_COLUMNS",
    "SCOPE_REQUIRED_COLUMNS",
    "RELEASE_SETS_REQUIRED_COLUMNS",
    "MANIFEST_REQUIRED_COLUMNS",
    "VALID_VARIABLE_TYPES",
    "validate_manifest",
    "validate_schema",
    "validate_schema_version",
    "warn_invalid_variable_types",
]


SCHEMA_VERSION: str = "2.0"

FileType = Literal["variables", "values", "scope", "release_sets", "manifest"]

MANIFEST_REQUIRED_COLUMNS: tuple[str, ...] = ("key", "value")
VARIABLES_REQUIRED_COLUMNS: tuple[str, ...] = (
    "variable_name",
    "variable_label",
    "variable_type",
    "release_set_id",
)
VALUE_LABELS_REQUIRED_COLUMNS: tuple[str, ...] = (
    "value_label_id",
    "value_labels_json",
    "value_labels_stata",
    "code_count",
)
SCOPE_REQUIRED_COLUMNS: tuple[str, ...] = ("scope_id", "scope_level_1", "release")
RELEASE_SETS_REQUIRED_COLUMNS: tuple[str, ...] = ("release_set_id", "scope_id")

VALID_VARIABLE_TYPES: frozenset[str] = frozenset(
    {"categorical", "continuous", "text", "date", "identifier", "binary", ""}
)


class SchemaError(ValueError):
    """Raised when a metadata file fails schema validation."""


class SchemaVersionError(SchemaError):
    """Raised when a bundle declares a ``schema_version`` other than ``2.0``."""


@dataclass
class Manifest:
    """Parsed representation of ``{domain}_manifest_{lang}.csv``.

    ``level_names`` is the machine-readable name per level
    (``scope_level_N_name``); ``level_titles`` is the human-readable
    title per level (``scope_level_N_title``), localized per language.
    Both have length ``scope_depth``.
    """

    domain: str
    schema_version: str
    publisher: str
    bundle_release_date: str
    languages: list[str]
    scope_depth: int
    level_names: list[str]
    level_titles: list[str]
    extra: dict[str, str] = field(default_factory=dict)


def validate_schema_version(schema_version: str | None) -> None:
    """Raise :class:`SchemaVersionError` when ``schema_version`` != ``"2.0"``.

    Mirrors ``_al_validate_schema`` lines 2174–2200. ``None`` or empty
    is treated as "no version tag found" and rejected with the same
    recovery hint as the Stata side.
    """
    if not schema_version:
        raise SchemaVersionError(
            "No schema version found in autolabel bundle.\n"
            f"autolabel requires schema_version = {SCHEMA_VERSION!r}.\n"
            "Solution: delete the cache directory and re-run update_datasets()."
        )
    if schema_version != SCHEMA_VERSION:
        raise SchemaVersionError(
            f"Schema version mismatch.\n"
            f"  Found:     {schema_version}\n"
            f"  Required:  {SCHEMA_VERSION}\n"
            "Solution: delete the cache directory and re-run update_datasets()."
        )


def validate_manifest(df: pd.DataFrame) -> Manifest:
    """Validate a manifest DataFrame and return the parsed :class:`Manifest`.

    Enforces:

    - ``key`` / ``value`` columns present
    - every required key populated (``domain``, ``schema_version``,
      ``publisher``, ``bundle_release_date``, ``languages``,
      ``scope_depth``, plus ``scope_level_{i}_name`` and
      ``scope_level_{i}_title`` for ``i`` in ``1..scope_depth``)
    - ``schema_version == "2.0"``

    Unknown keys are retained in :attr:`Manifest.extra` for consumers
    that want namespaced extensions (``domain:ext_*``).
    """
    for col in MANIFEST_REQUIRED_COLUMNS:
        if col not in df.columns:
            raise SchemaError(
                f"manifest file missing required column {col!r}; "
                f"expected columns {MANIFEST_REQUIRED_COLUMNS}."
            )

    kv: dict[str, str] = {}
    for key, value in zip(df["key"].astype(str), df["value"].astype(str), strict=False):
        kv[key.strip()] = "" if pd.isna(value) else str(value).strip()

    def _require(key: str) -> str:
        if key not in kv or kv[key] == "":
            raise SchemaError(f"manifest missing required key {key!r}.")
        return kv[key]

    schema_version = _require("schema_version")
    validate_schema_version(schema_version)

    domain = _require("domain")
    publisher = _require("publisher")
    bundle_release_date = _require("bundle_release_date")
    languages = [s.strip() for s in _require("languages").split("|") if s.strip()]

    try:
        scope_depth = int(_require("scope_depth"))
    except ValueError as exc:
        raise SchemaError(
            f"manifest key 'scope_depth' must be an integer, got {kv.get('scope_depth')!r}."
        ) from exc
    if scope_depth < 1:
        raise SchemaError(f"manifest key 'scope_depth' must be >= 1, got {scope_depth}.")

    level_names: list[str] = []
    level_titles: list[str] = []
    for i in range(1, scope_depth + 1):
        level_names.append(_require(f"scope_level_{i}_name"))
        level_titles.append(_require(f"scope_level_{i}_title"))

    known = {
        "domain",
        "schema_version",
        "publisher",
        "bundle_release_date",
        "languages",
        "scope_depth",
    }
    known.update(f"scope_level_{i}_name" for i in range(1, scope_depth + 1))
    known.update(f"scope_level_{i}_title" for i in range(1, scope_depth + 1))
    extra = {k: v for k, v in kv.items() if k not in known}

    return Manifest(
        domain=domain,
        schema_version=schema_version,
        publisher=publisher,
        bundle_release_date=bundle_release_date,
        languages=languages,
        scope_depth=scope_depth,
        level_names=level_names,
        level_titles=level_titles,
        extra=extra,
    )


def validate_schema(
    df: pd.DataFrame,
    file_type: FileType,
    *,
    scope_depth: int | None = None,
) -> None:
    """Validate ``df`` matches the column contract for ``file_type``.

    ``scope_depth`` is required when validating the ``scope`` file: the
    manifest declares the depth and the scope file must carry a
    ``scope_level_{i}`` column for each ``i`` in ``1..scope_depth``.
    """
    if file_type == "manifest":
        validate_manifest(df)
        return

    required = _REQUIRED_COLUMNS[file_type]
    for col in required:
        if col not in df.columns:
            raise SchemaError(
                f"{file_type} file missing required column {col!r}; "
                f"expected columns {required}."
            )

    if file_type == "scope" and scope_depth is not None:
        for i in range(1, scope_depth + 1):
            col = f"scope_level_{i}"
            if col not in df.columns:
                raise SchemaError(
                    f"scope file missing {col!r}; manifest declares "
                    f"scope_depth={scope_depth}."
                )


def warn_invalid_variable_types(df: pd.DataFrame) -> int:
    """Return the count of rows with non-standard ``variable_type`` values."""
    if "variable_type" not in df.columns:
        return 0
    types = df["variable_type"].fillna("").astype(str)
    invalid = ~types.isin(VALID_VARIABLE_TYPES)
    return int(invalid.sum())


_REQUIRED_COLUMNS: dict[str, tuple[str, ...]] = {
    "variables": VARIABLES_REQUIRED_COLUMNS,
    "values": VALUE_LABELS_REQUIRED_COLUMNS,
    "scope": SCOPE_REQUIRED_COLUMNS,
    "release_sets": RELEASE_SETS_REQUIRED_COLUMNS,
    "manifest": MANIFEST_REQUIRED_COLUMNS,
}
