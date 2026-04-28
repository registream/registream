"""Stata-parity test 11: telemetry config behavior.

Mirror of: ``registream/stata/tests/dofiles/11_telemetry_config.do``

Twelve sub-tests covering: field presence, defaults, set/get cycles,
internet_disabled effect on update checks, validation rejection (Python
``KeyError`` for unknown keys; type validation is statically enforced),
sequential sets, config path helper, missing-key handling, missing-file
handling, and auto-init on set.

Most behaviour is also covered by ``test_config.py`` and ``test_updates.py``;
this file re-asserts the contract under the per-dofile parity mapping.
"""

from __future__ import annotations

from dataclasses import fields
from pathlib import Path

import pytest

from registream.config import (
    CONFIG_FILENAME,
    Config,
    config_path,
    get,
    init,
    load,
    save,
    set_value,
)
from registream.updates import check_package


# ─── Test 1/12: Fresh config has all expected fields ──────────────────────────


def test_parity_11_fresh_config_has_all_fields(tmp_path: Path) -> None:
    """Stata: fresh config has 7 expected keys (usage_logging, telemetry_enabled,
    internet_access, auto_update_check, last_update_check, update_available,
    latest_version).
    """
    init(tmp_path)
    cfg = load(tmp_path)

    expected = {
        "usage_logging",
        "telemetry_enabled",
        "internet_access",
        "auto_update_check",
        "last_update_check",
        "update_available",
        "latest_version",
    }
    actual = {f.name for f in fields(cfg)}
    missing = expected - actual
    assert not missing, f"missing config fields: {missing}"


# ─── Test 2/12: Default telemetry_enabled = true ─────────────────────────────


def test_parity_11_default_telemetry_enabled_true(tmp_path: Path) -> None:
    """AUTO_APPROVE / Full Mode: telemetry_enabled defaults to true."""
    init(tmp_path)
    assert get("telemetry_enabled", tmp_path) is True


# ─── Test 3/12: Set telemetry_enabled to false ───────────────────────────────


def test_parity_11_set_telemetry_false(tmp_path: Path) -> None:
    init(tmp_path)
    set_value("telemetry_enabled", False, tmp_path)
    assert get("telemetry_enabled", tmp_path) is False


# ─── Test 4/12: Set telemetry_enabled back to true ───────────────────────────


def test_parity_11_toggle_telemetry_back_to_true(tmp_path: Path) -> None:
    init(tmp_path)
    set_value("telemetry_enabled", False, tmp_path)
    set_value("telemetry_enabled", True, tmp_path)
    assert get("telemetry_enabled", tmp_path) is True


# ─── Test 5/12: usage_logging is independent of telemetry ────────────────────


def test_parity_11_usage_logging_independent_of_telemetry(tmp_path: Path) -> None:
    """Local usage logging can be on while online telemetry is off."""
    init(tmp_path)
    set_value("telemetry_enabled", False, tmp_path)
    set_value("usage_logging", True, tmp_path)

    assert get("telemetry_enabled", tmp_path) is False
    assert get("usage_logging", tmp_path) is True


# ─── Test 6/12: internet_access=false disables update checks ─────────────────


def test_parity_11_internet_disabled_blocks_update_check(tmp_path: Path) -> None:
    """Stata: with ``internet_access=false``, ``check_package`` returns
    reason ``internet_disabled``.
    """
    init(tmp_path)
    set_value("internet_access", False, tmp_path)

    result = check_package("3.0.0", tmp_path)
    assert result.reason == "internet_disabled"


# ─── Test 7/12: Config validates input ───────────────────────────────────────


def test_parity_11_set_value_rejects_unknown_key(tmp_path: Path) -> None:
    """Stata: ``registream config, telemetry_enabled(invalid)`` exits rc=198.

    Python: ``set_value`` raises ``KeyError`` for unknown keys. Type
    validation of bool values is the caller's responsibility; Python's
    static typing handles that at the call site, not at runtime.
    """
    init(tmp_path)
    with pytest.raises(KeyError):
        set_value("not_a_real_key", True, tmp_path)


# ─── Test 8/12: Multiple sequential sets persist correctly ───────────────────


def test_parity_11_sequential_sets_persist(tmp_path: Path) -> None:
    init(tmp_path)
    set_value("usage_logging", False, tmp_path)
    set_value("telemetry_enabled", True, tmp_path)
    set_value("internet_access", False, tmp_path)
    set_value("auto_update_check", False, tmp_path)

    assert get("usage_logging", tmp_path) is False
    assert get("telemetry_enabled", tmp_path) is True
    assert get("internet_access", tmp_path) is False
    assert get("auto_update_check", tmp_path) is False


# ─── Test 9/12: Config path helper returns the right path ────────────────────


def test_parity_11_config_path_helper(tmp_path: Path) -> None:
    """Stata: ``_rs_config path`` returns the config file path.

    Python: ``config_path()`` returns ``<dir>/config_python.toml``
    (per-client filename, not Stata's CSV).
    """
    expected = tmp_path / CONFIG_FILENAME
    assert config_path(tmp_path) == expected


# ─── Test 10/12: Get on unknown key raises ───────────────────────────────────


def test_parity_11_get_on_unknown_key_raises(tmp_path: Path) -> None:
    """Stata: ``_rs_config get`` on missing key returns ``r(found)=0``.

    Python: ``get`` raises ``KeyError`` for unknown keys (stricter; fail
    loud rather than silent default). For *known* keys with missing values
    in the file, ``get`` falls back to the dataclass default; that case is
    covered by ``test_config.test_get_helper_returns_default_when_key_absent_from_file``.
    """
    init(tmp_path)
    with pytest.raises(KeyError):
        get("nonexistent_key_xyz", tmp_path)


# ─── Test 11/12: Get from missing file returns gracefully ────────────────────


def test_parity_11_get_from_missing_file_returns_default(tmp_path: Path) -> None:
    """Stata: get from missing config returns ``r(found)=0``.

    Python: ``load()`` on a missing file returns ``Config()`` defaults
    without crashing; ``get()`` on a known key returns the dataclass
    default.
    """
    # No init, no save; file doesn't exist in tmp_path
    assert not (tmp_path / CONFIG_FILENAME).exists()
    assert get("usage_logging", tmp_path) is True  # Config() default


# ─── Test 12/12: Set on missing file triggers auto-init ──────────────────────


def test_parity_11_set_value_creates_file_when_missing(tmp_path: Path) -> None:
    """Stata: ``_rs_config set`` on a missing config file triggers init."""
    assert not (tmp_path / CONFIG_FILENAME).exists()

    set_value("usage_logging", False, tmp_path)

    assert (tmp_path / CONFIG_FILENAME).exists()
    assert get("usage_logging", tmp_path) is False
