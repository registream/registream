"""Stata-parity test 06: comprehensive update system.

Mirror of: ``registream/stata/tests/dofiles/06_comprehensive_update_system.do``

Seven sub-tests. Several overlap with config.py tests; for those the parity
test re-asserts the contract via the updates module's API (which is the
new surface in this checkpoint).
"""

from __future__ import annotations

from dataclasses import fields
from pathlib import Path

from registream.config import Config, init, load, save
from registream.updates import HeartbeatResult, check_package


# ─── Test 1/7: Config does NOT contain a `version` field ──────────────────────


def test_parity_06_config_has_no_version_field() -> None:
    """Stata: ensures config_stata.csv has no `version` key.

    Python: the ``Config`` dataclass must not have a ``version`` field;
    version comes from package metadata, not config.
    """
    field_names = {f.name for f in fields(Config)}
    assert "version" not in field_names


# ─── Test 2/7: Version comes from code, not config ────────────────────────────


def test_parity_06_version_from_package_metadata() -> None:
    """Stata: ``_rs_utils get_version`` returns a non-empty string.

    Python: ``importlib.metadata.version("registream-core")`` returns the
    installed version. Also covered by parity test 08.
    """
    from importlib.metadata import version
    assert version("registream-core")


# ─── Test 3/7: Read-only / writable handling ──────────────────────────────────


def test_parity_06_writable_set_get_round_trip(tmp_path: Path) -> None:
    """Stata: set then get on a writable directory should round-trip."""
    save(Config(usage_logging=True), tmp_path)
    cfg = load(tmp_path)
    cfg.usage_logging = False
    save(cfg, tmp_path)

    assert load(tmp_path).usage_logging is False


# ─── Test 4/7: check_package returns structured results ──────────────────────


def test_parity_06_check_package_returns_structured_result(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    """Stata: ``check_package`` returns ``r(reason)``, ``r(update_available)``, etc.

    Python: ``check_package`` returns a ``HeartbeatResult`` dataclass with
    typed fields.
    """
    save(Config(internet_access=True, last_update_check=None), tmp_path)
    result = check_package("3.0.0", tmp_path)

    assert isinstance(result, HeartbeatResult)
    assert result.reason  # non-empty
    assert result.reason in {"success", "cached", "network_error", "internet_disabled"}


# ─── Test 5/7: Update check with internet disabled ────────────────────────────


def test_parity_06_check_package_internet_disabled(tmp_path: Path) -> None:
    """Stata: with ``internet_access=false``, reason should be ``internet_disabled``."""
    save(Config(internet_access=False), tmp_path)
    result = check_package("3.0.0", tmp_path)
    assert result.reason == "internet_disabled"


# ─── Test 6/7: Multiple config values persist ────────────────────────────────


def test_parity_06_multiple_config_values_persist(tmp_path: Path) -> None:
    """Stata: setting multiple keys and reading back works."""
    cfg = Config(telemetry_enabled=False, auto_update_check=False)
    save(cfg, tmp_path)

    loaded = load(tmp_path)
    assert loaded.telemetry_enabled is False
    assert loaded.auto_update_check is False


# ─── Test 7/7: Init on impossible path returns gracefully ─────────────────────


def test_parity_06_init_on_impossible_path_does_not_crash() -> None:
    """Stata: ``_rs_config init`` on a non-creatable path returns gracefully.

    Python: ``init()`` on a read-only path catches ``OSError`` and returns
    in-memory defaults.
    """
    impossible = Path("/nonexistent_path_for_test_12345/registream")
    cfg = init(impossible)
    # Returns defaults instead of crashing
    assert cfg.usage_logging is True  # default value
