"""Stata-parity test 01: config initialization.

Mirror of: ``registream/stata/tests/dofiles/01_config_initialization.do``

Six sub-tests: create, verify, check defaults, round-trip modifications,
and validate the on-disk format (TOML for Python, CSV for Stata).
"""

from __future__ import annotations

import tomllib
from pathlib import Path

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


# ─── Test 1/6: delete config file, verify gone ─────────────────────────────────


def test_parity_01_delete_config_and_verify_removal(tmp_path: Path) -> None:
    """Stata: ``cap erase config_stata.csv`` then ``cap confirm file``.

    Python equivalent: write a config, delete it, confirm absence.
    """
    save(Config(), tmp_path)
    path = config_path(tmp_path)
    assert path.exists()

    path.unlink()
    assert not path.exists()


# ─── Test 2/6: init triggers config creation ───────────────────────────────────


def test_parity_01_init_creates_config_file(tmp_path: Path) -> None:
    """Stata: ``registream info`` triggers ``_rs_config init`` which creates the file.

    Python equivalent: calling ``registream.config.init()`` creates the file.
    The eventual ``registream.info()`` function will call ``init()`` internally
    and produce the same observable effect.
    """
    path = config_path(tmp_path)
    assert not path.exists()

    init(tmp_path)
    assert path.exists()


# ─── Test 3/6: file exists after init ─────────────────────────────────────────


def test_parity_01_file_exists_after_init(tmp_path: Path) -> None:
    init(tmp_path)
    assert config_path(tmp_path).exists()


# ─── Test 4/6: defaults match AUTO_APPROVE / Full Mode ─────────────────────────


def test_parity_01_defaults_match_full_mode(tmp_path: Path) -> None:
    """Stata test 4: defaults are usage=true, telemetry=true, internet=true.

    Python parity: same defaults; Full Mode is the AUTO_APPROVE preset on
    both sides, and Python's ``Config()`` defaults match.
    """
    init(tmp_path)
    cfg = load(tmp_path)

    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True


def test_parity_01_defaults_via_get_helper(tmp_path: Path) -> None:
    """Same as above but via the Stata-style ``get()`` helper API."""
    init(tmp_path)

    assert get("usage_logging", tmp_path) is True
    assert get("telemetry_enabled", tmp_path) is True
    assert get("internet_access", tmp_path) is True
    assert get("auto_update_check", tmp_path) is True


# ─── Test 5/6: modify and verify persistence ───────────────────────────────────


def test_parity_01_modification_persists(tmp_path: Path) -> None:
    """Stata test 5: ``_rs_config set usage_logging false`` → readback returns false."""
    init(tmp_path)
    set_value("usage_logging", False, tmp_path)

    # Stata-style helper readback:
    assert get("usage_logging", tmp_path) is False
    # Pythonic readback (also confirms file persistence, not just in-memory):
    assert load(tmp_path).usage_logging is False


# ─── Test 6/6: format check (TOML for Python instead of CSV) ───────────────────


def test_parity_01_python_uses_toml_at_per_client_filename(tmp_path: Path) -> None:
    """Stata test 6: verify simple ``key;value`` CSV format with header ``key;value``.

    Python parity (adapted): verify the file is at ``config_python.toml``
    (NOT ``config_stata.csv``) and parses as valid TOML with the expected
    top-level keys.
    """
    init(tmp_path)
    path = config_path(tmp_path)

    # Per-client filename: Python writes its own file, never the Stata one.
    assert path.name == CONFIG_FILENAME == "config_python.toml"
    assert not (tmp_path / "config_stata.csv").exists()

    # Content parses as valid TOML.
    with path.open("rb") as fh:
        data = tomllib.load(fh)

    # And contains the expected keys (the Stata-equivalent fields).
    for expected_key in (
        "usage_logging",
        "telemetry_enabled",
        "internet_access",
        "auto_update_check",
    ):
        assert expected_key in data, f"missing key in config_python.toml: {expected_key}"
