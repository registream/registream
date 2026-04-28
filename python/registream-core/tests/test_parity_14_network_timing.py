"""Stata-parity test 14: network requests timing & error handling.

Mirror of: ``registream/stata/tests/dofiles/14_network_requests_timing.do``

Five sub-tests covering API host resolution, timing, the heartbeat send
mechanism, offline mode, and graceful network error handling.
"""

from __future__ import annotations

import time
from pathlib import Path

from registream.config import Config, save
from registream.updates import (
    NETWORK_TIMEOUT_SECONDS,
    HeartbeatResult,
    check_package,
    send_heartbeat,
)
from registream.utils import get_api_host


# ─── Test 1/5: API host resolution ───────────────────────────────────────────


def test_parity_14_api_host_resolution() -> None:
    """Stata: ``_rs_utils get_api_host`` returns a non-empty host.

    Python: ``registream.utils.get_api_host()`` returns the production URL.
    Also covered by test_utils.test_get_api_host_default.
    """
    host = get_api_host()
    assert host
    assert host.startswith("http")


# ─── Test 2/5: Version check completes (does not hang) ───────────────────────


def test_parity_14_check_package_completes_quickly(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    """Stata: ``check_package`` completes in reasonable time (does not hang).

    Python: with a mocked HTTP response, ``check_package`` returns
    near-instantly; much faster than the network timeout.
    """
    save(Config(internet_access=True, last_update_check=None), tmp_path)

    start = time.monotonic()
    result = check_package("3.0.0", tmp_path)
    elapsed = time.monotonic() - start

    assert isinstance(result, HeartbeatResult)
    assert elapsed < NETWORK_TIMEOUT_SECONDS  # mocked → essentially zero
    assert result.reason  # non-empty


# ─── Test 3/5: Heartbeat send mechanism ──────────────────────────────────────


def test_parity_14_send_heartbeat_completes(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    """Stata: ``send_heartbeat`` completes without erroring."""
    save(
        Config(
            telemetry_enabled=True,
            internet_access=True,
            auto_update_check=True,
            last_update_check=None,
        ),
        tmp_path,
    )
    result = send_heartbeat("3.0.0", "registream info", tmp_path)
    assert result.reason in {"success", "cached"}


# ─── Test 4/5: Offline mode blocks network ──────────────────────────────────


def test_parity_14_offline_mode_blocks_network(tmp_path: Path) -> None:
    """Stata: with ``internet_access=false``, ``check_package`` returns
    ``internet_disabled``.
    """
    save(Config(internet_access=False), tmp_path)
    result = check_package("3.0.0", tmp_path)
    assert result.reason == "internet_disabled"


# ─── Test 5/5: Network error handling ───────────────────────────────────────


def test_parity_14_network_error_returns_network_error(
    tmp_path: Path,
    mock_network_error: None,
) -> None:
    """Stata: invalid host or network failure returns ``reason='network_error'``.

    Python: same; ``requests.RequestException`` is caught and returned as
    ``reason='network_error'`` rather than crashing.
    """
    save(Config(internet_access=True, last_update_check=None), tmp_path)
    result = check_package("3.0.0", tmp_path)
    assert result.reason == "network_error"
