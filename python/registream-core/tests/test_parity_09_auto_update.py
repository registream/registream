"""Stata-parity test 09: auto update check behavior.

Mirror of: ``registream/stata/tests/dofiles/09_auto_update_check.do``

Six sub-tests covering: config field presence, info() display, toggle,
heartbeat respecting the disabled flag, notification display, and the
24-hour cache via ``last_update_check``.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from registream.config import Config, load, save
from registream.info import info
from registream.updates import HeartbeatResult, send_heartbeat, show_notification


# ─── Test 1/6: Config has auto_update_check field ────────────────────────────


def test_parity_09_config_has_auto_update_check() -> None:
    """Stata: config has ``auto_update_check`` field."""
    cfg = Config()
    assert hasattr(cfg, "auto_update_check")


# ─── Test 2/6: Info shows the setting ────────────────────────────────────────


def test_parity_09_info_shows_auto_update_check(tmp_path: Path) -> None:
    """Stata: ``registream info`` displays the ``auto_update_check`` setting.

    Python: ``info()`` output includes the ``auto_update_check`` field.
    """
    text = info(tmp_path)
    assert "auto_update_check" in text


# ─── Test 3/6: Config can toggle auto_update_check ───────────────────────────


def test_parity_09_toggle_auto_update_check(tmp_path: Path) -> None:
    """Stata: ``registream config, auto_update_check(false)`` then back to true."""
    save(Config(auto_update_check=True), tmp_path)
    cfg = load(tmp_path)
    cfg.auto_update_check = False
    save(cfg, tmp_path)
    assert load(tmp_path).auto_update_check is False

    cfg.auto_update_check = True
    save(cfg, tmp_path)
    assert load(tmp_path).auto_update_check is True


# ─── Test 4/6: Background check respects auto_update_check=false ─────────────


def test_parity_09_heartbeat_skipped_when_disabled(tmp_path: Path) -> None:
    """Stata: ``send_heartbeat`` exits early when ``auto_update_check=false``
    AND ``telemetry_enabled=false``.

    Python: same behavior; early exit with reason="success" and no
    ``update_available`` set.
    """
    save(
        Config(
            auto_update_check=False,
            telemetry_enabled=False,
            last_update_check=None,
        ),
        tmp_path,
    )
    # No HTTP mock; if network were called, the test would error out
    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.update_available is False


# ─── Test 5/6: Notification display ──────────────────────────────────────────


def test_parity_09_show_notification_runs() -> None:
    """Stata: ``show_notification`` runs without error and prints banner.

    Python: ``show_notification`` returns the banner text without raising.
    """
    result = HeartbeatResult(update_available=True, latest_version="99.0.0")
    text = show_notification("3.0.0", result)
    assert text  # non-empty banner
    assert "99.0.0" in text


# ─── Test 6/6: 24-hour cache via last_update_check timestamp ─────────────────


def test_parity_09_cache_persists_via_last_update_check(tmp_path: Path) -> None:
    """Stata: ``last_update_check`` timestamp is stored in config and survives
    a save/load round-trip.
    """
    now = datetime.now(timezone.utc)
    save(Config(last_update_check=now), tmp_path)

    loaded = load(tmp_path)
    assert loaded.last_update_check is not None
    # Allow tiny serialization deltas
    assert abs((loaded.last_update_check - now).total_seconds()) < 1


def test_parity_09_24h_cache_returns_cached_when_fresh(tmp_path: Path) -> None:
    """A heartbeat within 24h of last check returns ``reason='cached'``."""
    cfg = Config(
        last_update_check=datetime.now(timezone.utc) - timedelta(hours=12),
        update_available=True,
        latest_version="42.0.0",
    )
    save(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "cached"
    assert result.latest_version == "42.0.0"
