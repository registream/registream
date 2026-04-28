"""Stata-parity test 13: version resolution priority.

Mirror of: ``registream/stata/tests/dofiles/13_version_resolution_priority.do``

Note: several Stata sub-tests do not translate cleanly to Python because
Python's version comes from package metadata (``importlib.metadata``), not
from a hardcoded constant or runtime override hook. Those sub-tests are
explicitly skipped with documented reasons rather than silently omitted.
"""

from __future__ import annotations

import re

import pytest


# ─── Test 1/6: get_version returns a version string ──────────────────────────


def test_parity_13_version_returns_non_empty_string() -> None:
    """Stata: ``_rs_utils get_version`` returns non-empty.

    Python: ``importlib.metadata.version("registream-core")`` returns non-empty.
    """
    from importlib.metadata import version
    v = version("registream-core")
    assert v
    assert isinstance(v, str)


# ─── Test 2/6: Dev override (no Python equivalent) ───────────────────────────


@pytest.mark.skip(
    reason="Stata uses $REGISTREAM_TEST_VERSION + dev .ado override; "
    "Python's importlib.metadata reads from installed package metadata. "
    "To 'override', install a different version of registream-core."
)
def test_parity_13_dev_override() -> None:
    """Stata: ``$REGISTREAM_TEST_VERSION`` overrides version reporting.

    Python equivalent: there is no env-var override for the version. The
    only way to test against a different version is to install it via
    ``uv add registream-core==X.Y.Z``. Intentionally skipped.
    """
    raise NotImplementedError


# ─── Test 3/6: Version is X.Y.Z format ───────────────────────────────────────


def test_parity_13_version_is_semver_format() -> None:
    """Stata: version matches X.Y.Z (or pre-release variant)."""
    from importlib.metadata import version
    v = version("registream-core")
    assert re.match(r"^\d+\.\d+\.\d+", v), f"version {v!r} does not match X.Y.Z"


# ─── Test 4/6: Core version helper ───────────────────────────────────────────


def test_parity_13_core_version_via_metadata() -> None:
    """Stata: ``_rs_get_core_version`` returns the core version.

    Python: ``importlib.metadata.version("registream-core")`` is the
    canonical core version source.
    """
    from importlib.metadata import version
    assert version("registream-core")


# ─── Test 5/6: Min version check (NOT NEEDED in Python) ──────────────────────


@pytest.mark.skip(
    reason="Stata `_rs_check_core_version` exists because Stata has no "
    "dependency resolver. Python uses pip's version constraints "
    "(`registream-core>=3.0,<4.0` in pyproject.toml); pip handles this "
    "at install time. No runtime check needed."
)
def test_parity_13_check_core_version() -> None:
    raise NotImplementedError


# ─── Test 6/6: Autolabel version tracking (Phase 2 deferred) ─────────────────


@pytest.mark.skip(reason="autolabel module ports in Phase 2")
def test_parity_13_autolabel_version_tracking() -> None:
    """When autolabel is installed, ``importlib.metadata.version('registream-autolabel')``
    returns its version. Tested in the autolabel-side parity tests during Phase 2.
    """
    raise NotImplementedError
