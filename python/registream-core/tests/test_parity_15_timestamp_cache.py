"""Stata-parity test 15: timestamp cache logic.

Mirror of: ``registream/stata/tests/dofiles/15_timestamp_cache_test.do``

Six sub-tests of pure 24-hour cache arithmetic. The Stata version uses
millisecond clock arithmetic (`clock(...)` returning ms since 1960); the
Python equivalent uses ``datetime`` and ``timedelta``. The cache logic
itself lives in ``registream.updates.send_heartbeat``; these tests
exercise that logic end-to-end via the public API.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from registream.config import Config, save
from registream.updates import CACHE_HOURS, send_heartbeat


# ─── Test 1/6: Current time is a valid datetime ───────────────────────────────


def test_parity_15_current_time_is_valid_datetime() -> None:
    """Stata: ``clock(...)`` returns a valid timestamp.

    Python: ``datetime.now(timezone.utc)`` returns a tz-aware datetime.
    """
    now = datetime.now(timezone.utc)
    assert isinstance(now, datetime)
    assert now.tzinfo is timezone.utc


# ─── Test 2/6: 24-hour difference computation ────────────────────────────────


def test_parity_15_24h_difference_computation() -> None:
    """Stata: 24h = 86,400,000 ms. Python: ``timedelta(hours=24)``."""
    now = datetime.now(timezone.utc)
    yesterday = now - timedelta(hours=24)
    diff = now - yesterday

    assert diff == timedelta(hours=24)
    assert diff.total_seconds() == 86_400


# ─── Test 3/6: Cache stale after >24h triggers fresh fetch ───────────────────


def test_parity_15_cache_stale_after_25h(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """Stata: 25h-old timestamp is stale.

    Python: ``send_heartbeat`` with ``last_update_check`` 25h ago should
    NOT return cached. With the heartbeat fixture mocked, the function
    falls through to fetch and returns ``reason='success'`` with the
    fresh response (which the fixture says has no update).
    """
    cfg = Config(
        last_update_check=datetime.now(timezone.utc) - timedelta(hours=25),
        update_available=True,         # cached value that should NOT be returned
        latest_version="42.0.0",       # cached value that should NOT be returned
    )
    save(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason != "cached"
    assert result.reason == "success"
    # The fresh fetch (mocked) overwrote the stale cached values
    assert result.update_available is False
    assert result.latest_version == ""


# ─── Test 4/6: Cache fresh within <24h returns cached ────────────────────────


def test_parity_15_cache_fresh_within_24h(tmp_path: Path) -> None:
    """Stata: 1h-old timestamp is fresh.

    Python: ``send_heartbeat`` with ``last_update_check`` 1h ago returns
    ``reason='cached'`` and the cached values, without hitting the network.
    """
    cfg = Config(
        last_update_check=datetime.now(timezone.utc) - timedelta(hours=1),
        update_available=True,
        latest_version="42.0.0",
    )
    save(cfg, tmp_path)

    # No HTTP mock; if network were called, the test would error out
    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "cached"
    assert result.update_available is True
    assert result.latest_version == "42.0.0"


# ─── Test 5/6: Empty timestamp triggers check ────────────────────────────────


def test_parity_15_empty_timestamp_triggers_check(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """Stata: empty ``last_update_check`` triggers an update check.

    Python: ``last_update_check=None`` triggers a fresh fetch on the very
    first heartbeat (no cache to check against).
    """
    cfg = Config(last_update_check=None)
    save(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    # No cache → fetched fresh → reason="success" (mocked)
    assert result.reason == "success"


# ─── Test 6/6: Past-the-boundary timestamp triggers check ────────────────────


def test_parity_15_past_boundary_triggers_check(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """Stata: a timestamp at or past the 24h boundary triggers a check.

    Python: cache check is ``now - last < timedelta(hours=24)`` (strict
    less-than), so anything ≥ 24h old falls through to fetch. We use
    24h+1s to be safely past the boundary.
    """
    cfg = Config(
        last_update_check=datetime.now(timezone.utc)
        - timedelta(hours=CACHE_HOURS, seconds=1),
    )
    save(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "success"  # cache stale → fetched
