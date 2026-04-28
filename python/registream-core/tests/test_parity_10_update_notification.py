"""Stata-parity test 10: update notification flow.

Mirror of: ``registream/stata/tests/dofiles/10_update_notification.do``

Five sub-tests, the last of which (semantic version comparison) is broken
out into multiple parametrized cases.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from registream.config import Config, init, load, save
from registream.updates import (
    HeartbeatResult,
    compare_versions,
    send_heartbeat,
    show_notification,
)


# ─── Test 1/5: Simulate update via config persistence ────────────────────────


def test_parity_10_simulated_update_persists_in_config(tmp_path: Path) -> None:
    """Stata: write update_available=true and latest_version, read back."""
    save(Config(update_available=True, latest_version="99.0.0"), tmp_path)

    loaded = load(tmp_path)
    assert loaded.update_available is True
    assert loaded.latest_version == "99.0.0"


# ─── Test 2/5: Background check sets state from cache ────────────────────────


def test_parity_10_background_check_reads_cache(tmp_path: Path) -> None:
    """With a fresh ``last_update_check``, ``send_heartbeat`` reads the
    cached values and returns them via the result.
    """
    cfg = Config(
        last_update_check=datetime.now(timezone.utc),
        update_available=True,
        latest_version="99.0.0",
    )
    save(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "cached"
    assert result.update_available is True
    assert result.latest_version == "99.0.0"


# ─── Test 3/5: Config persists across re-init ────────────────────────────────


def test_parity_10_re_init_preserves_existing_config(tmp_path: Path) -> None:
    """Stata: ``_rs_config init`` does NOT overwrite an existing config."""
    save(Config(update_available=True, latest_version="42.0.0"), tmp_path)

    init(tmp_path)
    loaded = load(tmp_path)
    assert loaded.update_available is True
    assert loaded.latest_version == "42.0.0"


# ─── Test 4/5: Notification displays when update available ──────────────────


def test_parity_10_notification_displays_with_update() -> None:
    result = HeartbeatResult(update_available=True, latest_version="99.0.0")
    text = show_notification("3.0.0", result)
    assert text
    assert "99.0.0" in text


def test_parity_10_notification_empty_without_update() -> None:
    result = HeartbeatResult(update_available=False)
    assert show_notification("3.0.0", result) == ""


# ─── Test 5/5: Semantic version comparison ──────────────────────────────────


def test_parity_10_semver_major_bump() -> None:
    """1.0.0 < 2.0.0 → update available (major)."""
    assert compare_versions("1.0.0", "2.0.0") is True


def test_parity_10_semver_minor_bump() -> None:
    """2.0.0 < 2.1.0 → update available (minor)."""
    assert compare_versions("2.0.0", "2.1.0") is True


def test_parity_10_semver_patch_bump() -> None:
    """2.1.0 < 2.1.1 → update available (patch)."""
    assert compare_versions("2.1.0", "2.1.1") is True


def test_parity_10_semver_equal_no_update() -> None:
    """2.0.0 == 2.0.0 → no update."""
    assert compare_versions("2.0.0", "2.0.0") is False


def test_parity_10_semver_downgrade_no_update() -> None:
    """3.0.0 → 2.0.0 (downgrade) → no update."""
    assert compare_versions("3.0.0", "2.0.0") is False
