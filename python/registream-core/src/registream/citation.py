"""RegiStream citation text: parity with Stata ``registream cite``.

:func:`cite` returns the full Stata-style multi-line block (header rules,
"To cite RegiStream..." lead-in, the versioned APA line, and the
"Installed datasets:" list). :func:`cite_bibtex` returns the BibTeX entry.
Callers print the result themselves.

Title, authors, URL, and templates are sourced from ``_citation_data``
which is generated from ``registream/citations.yaml`` by
``registream/tools/render_citations.py``. Do not hand-edit constants here
edit the YAML and regenerate.
"""

from __future__ import annotations

import csv
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

from . import _citation_data as _cd

__all__ = ["cite", "cite_bibtex"]


_HLINE = "-" * 60


def cite(versioned: bool = True, directory: Path | str | None = None) -> str:
    """Return the full citation block, matching Stata's ``registream cite``.

    The block includes horizontal rules, the "To cite RegiStream..."
    lead-in, the APA line (versioned by default), and an "Installed
    datasets:" section sourced from ``<registream_dir>/autolabel/datasets.csv``.

    Pass ``versioned=False`` to omit the version string in the APA line.
    """
    if versioned:
        apa = _cd.APA_VERSIONED_TEMPLATE.format(version=_installed_version())
    else:
        apa = _cd.APA

    datasets_lines = _format_installed_datasets(directory)

    lines = [
        "",
        _HLINE,
        "Citation",
        _HLINE,
        "",
        "To cite RegiStream in publications, please use:",
        "",
        f"  {apa}",
        "",
        "Installed datasets:",
        "",
        *datasets_lines,
        "",
        _HLINE,
        "",
    ]
    return "\n".join(lines)


def cite_bibtex() -> str:
    """Return the BibTeX entry as a multi-line string.

    Always version-pinned to the installed ``registream-core`` version.
    """
    return _cd.BIBTEX_VERSIONED_TEMPLATE.replace("{{VERSION}}", _installed_version())


def _installed_version() -> str:
    """Return the installed ``registream-core`` version, or ``'unknown'``."""
    try:
        return version("registream-core")
    except PackageNotFoundError:
        return "unknown"


def _format_installed_datasets(directory: Path | str | None) -> list[str]:
    """Read ``<registream_dir>/autolabel/datasets.csv`` and format bullet lines.

    One bullet per unique (domain, version) pair; the registry has one row
    per cached file (variables/values/scope/... × language), so we dedup up
    to the (domain, version) level the user actually cares about. Each line
    ends with the catalog URL for that domain so users can look up provider
    details, source attribution, and version history.

    Returns ``["  (none installed yet)"]`` if the registry is missing or
    empty.
    """
    csv_path = _datasets_csv_path(directory)
    if csv_path is None or not csv_path.exists():
        return ["  (none installed yet)"]

    seen: set[tuple[str, str]] = set()
    rows: list[str] = []
    try:
        with open(csv_path, encoding="utf-8", newline="") as fh:
            reader = csv.reader(fh, delimiter=";")
            header = next(reader, None)
            if header is None:
                return ["  (none installed yet)"]
            # datasets.csv columns:
            # dataset_key;domain;type;lang;version;schema;downloaded;source;file_size;last_checked
            for row in reader:
                if not row:
                    continue
                domain = row[1].strip() if len(row) > 1 else ""
                version = row[4].strip() if len(row) > 4 else ""
                if not (domain and version):
                    continue
                key = (domain, version)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(
                    f"  \u2022 {domain} v{version} \u2014 "
                    f"https://registream.org/catalog/{domain}"
                )
    except OSError:
        return ["  (none installed yet)"]

    return rows or ["  (none installed yet)"]


def _datasets_csv_path(directory: Path | str | None) -> Path | None:
    """Resolve the ``datasets.csv`` path the same way Stata does.

    Stata does simple path concatenation: ``<registream_dir>/autolabel/datasets.csv``.
    We avoid importing from ``registream.autolabel`` (reverse dep) and
    just build the path ourselves.
    """
    try:
        from registream.dirs import get_registream_dir
    except ImportError:
        return None
    base = Path(directory).expanduser() if directory is not None else get_registream_dir()
    return base / "autolabel" / "datasets.csv"
