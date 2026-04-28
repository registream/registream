"""Unit tests for registream.citation."""

from __future__ import annotations

from importlib.metadata import version

from registream.citation import cite, cite_bibtex


# ─── cite() ────────────────────────────────────────────────────────────────────


def test_cite_default_includes_authors_and_url() -> None:
    text = cite()
    assert "Clark, J. & Wen, J." in text
    assert "https://registream.org" in text
    assert "RegiStream" in text


def test_cite_default_is_versioned() -> None:
    text = cite()
    installed = version("registream-core")
    assert f"Version {installed}" in text


def test_cite_unversioned_omits_version_string() -> None:
    text = cite(versioned=False)
    assert "Version" not in text
    assert "Clark, J. & Wen, J." in text
    assert "https://registream.org" in text


def test_cite_returns_string_not_none() -> None:
    assert isinstance(cite(), str)
    assert cite() != ""


# ─── cite_bibtex() ─────────────────────────────────────────────────────────────


def test_cite_bibtex_has_required_fields() -> None:
    bib = cite_bibtex()
    assert "@software{clark2024registream," in bib
    assert "author" in bib
    assert "title" in bib
    assert "version" in bib
    assert "year" in bib
    assert "url" in bib


def test_cite_bibtex_includes_installed_version() -> None:
    installed = version("registream-core")
    assert f"version = {{{installed}}}" in cite_bibtex()


def test_cite_bibtex_brace_balance() -> None:
    """The BibTeX must have balanced braces; common f-string mistake."""
    bib = cite_bibtex()
    assert bib.count("{") == bib.count("}")
