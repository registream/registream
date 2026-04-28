"""Stata-parity test 08: `registream version`, `registream cite`, `registream info`.

Mirror of: `registream/stata/tests/dofiles/08_version_and_cite_commands.do`

Asserts the same observable outcomes as the Stata test:

1. The version helper returns a non-empty string identifying the installed
   core distribution. (Stata: `_rs_utils get_version` returns `r(version)`.)
2. The citation command returns successfully and produces non-empty content.
   (Stata: `registream cite` runs without error and prints citation text.)
3. The info command returns successfully. (Stata: `registream info` runs
   without error.); **deferred**: `registream.info()` requires `config.py`,
   which ports in the next Phase 1 checkpoint. The skip is intentional and
   will be removed when info() lands.
"""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

import pytest

from registream.citation import cite, cite_bibtex


# ─── Test 1/3: registream version ──────────────────────────────────────────────


def test_parity_08_version_returns_non_empty_string() -> None:
    """Stata: `registream version` runs and `_rs_utils get_version` returns non-empty.

    Python equivalent: `importlib.metadata.version("registream-core")` returns
    a non-empty string. There is no `registream.__version__` because
    `registream` is a PEP 420 namespace package; the matrix in 08 lists
    `registream.__version__` as shorthand, but the realised import is via
    `importlib.metadata`.
    """
    try:
        v = version("registream-core")
    except PackageNotFoundError:
        pytest.fail("registream-core is not installed in this environment")

    assert v, "version string must not be empty"
    assert isinstance(v, str)
    # Loose SemVer-ish shape check: at least one dot.
    assert "." in v


# ─── Test 2/3: registream cite ─────────────────────────────────────────────────


def test_parity_08_cite_runs_and_returns_canonical_text() -> None:
    """Stata: `registream cite` runs successfully and prints citation text.

    Python equivalent: `from registream.citation import cite; cite()` returns
    the canonical citation containing the authors, title, URL, and the
    installed version.
    """
    text = cite()

    # Same content the Stata _registream_cite function prints. Title pulled
    # from the generated _citation_data module so this test catches drift
    # between the YAML master and the rendered module.
    from registream import _citation_data as _cd

    assert _cd.AUTHORS_APA in text
    assert "RegiStream" in text
    assert _cd.TITLE in text
    assert _cd.URL in text

    # Versioned by default, matches the Stata version-specific block.
    installed = version("registream-core")
    assert f"Version {installed}" in text


def test_parity_08_cite_bibtex_matches_stata_template() -> None:
    """The BibTeX entry must match the Stata `_registream_cite` template."""
    from registream import _citation_data as _cd

    bib = cite_bibtex()
    assert f"@{_cd.BIBTEX_KEY}" in bib or f"@software{{{_cd.BIBTEX_KEY}," in bib
    assert "Clark, Jeffrey and Wen, Jie" in bib
    assert _cd.TITLE in bib
    assert _cd.URL in bib

    installed = version("registream-core")
    assert f"version = {{{installed}}}" in bib


# ─── Test 3/3: registream info ────────────────────────────────────────────────


def test_parity_08_info_runs_without_error(tmp_path) -> None:
    """Stata: ``registream info`` runs successfully.

    Python equivalent: ``registream.info.info()`` returns a non-empty
    string containing the configuration display. The Stata test only checks
    that the command runs (rc=0); the Python equivalent additionally checks
    that the returned string contains the expected labels.
    """
    from registream.info import info

    text = info(tmp_path)
    assert text
    assert "RegiStream" in text
    assert "Configuration" in text
