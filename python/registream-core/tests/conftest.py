"""Shared pytest fixtures for registream-core tests.

Two flavours of fixtures live here:

1. **Isolation fixtures**: give each test its own ``REGISTREAM_DIR`` so
   tests cannot accidentally read or write the user's real
   ``~/.registream/`` directory.

2. **HTTP mock fixtures**: replace ``registream.updates.requests.get``
   with a stub that returns canned heartbeat responses (or raises a
   network error). Tests opt in by listing the fixture name in their
   parameters.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

import pytest
import requests


# ─── Isolation ────────────────────────────────────────────────────────────────


@pytest.fixture
def isolated_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Provide an isolated registream directory for the test.

    Sets ``REGISTREAM_DIR`` to ``tmp_path`` so any code calling
    :func:`registream.dirs.get_registream_dir` sees an empty directory
    unique to this test. Yields the path so tests can populate it directly.
    """
    monkeypatch.setenv("REGISTREAM_DIR", str(tmp_path))
    return tmp_path


# ─── HTTP mock helpers ────────────────────────────────────────────────────────


def _mock_response(body: str, status: int = 200) -> MagicMock:
    """Build a MagicMock that quacks like a :class:`requests.Response`."""
    response = MagicMock()
    response.text = body
    response.status_code = status
    response.raise_for_status = MagicMock()
    return response


@pytest.fixture
def mock_heartbeat_success(monkeypatch: pytest.MonkeyPatch) -> None:
    """Mock the heartbeat endpoint to return an update-available response."""

    def _get(url, timeout=None, **kwargs):  # noqa: ARG001
        return _mock_response(
            "registream_update=true\n"
            "registream_latest=99.0.0\n"
            "autolabel_update=false\n"
            "autolabel_latest=\n"
        )

    monkeypatch.setattr("registream.updates.requests.get", _get)


@pytest.fixture
def mock_heartbeat_no_update(monkeypatch: pytest.MonkeyPatch) -> None:
    """Mock the heartbeat endpoint to return a no-update response."""

    def _get(url, timeout=None, **kwargs):  # noqa: ARG001
        return _mock_response(
            "registream_update=false\n"
            "registream_latest=\n"
            "autolabel_update=false\n"
            "autolabel_latest=\n"
        )

    monkeypatch.setattr("registream.updates.requests.get", _get)


@pytest.fixture
def mock_heartbeat_with_autolabel_update(monkeypatch: pytest.MonkeyPatch) -> None:
    """Mock the heartbeat endpoint to return updates for both core and autolabel."""

    def _get(url, timeout=None, **kwargs):  # noqa: ARG001
        return _mock_response(
            "registream_update=true\n"
            "registream_latest=99.0.0\n"
            "autolabel_update=true\n"
            "autolabel_latest=99.5.0\n"
        )

    monkeypatch.setattr("registream.updates.requests.get", _get)


@pytest.fixture
def mock_network_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """Mock the heartbeat endpoint to raise a connection error."""

    def _get(url, timeout=None, **kwargs):  # noqa: ARG001
        raise requests.ConnectionError("simulated network failure")

    monkeypatch.setattr("registream.updates.requests.get", _get)


@pytest.fixture
def captured_heartbeat_url(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """Capture every URL passed to ``requests.get`` for inspection.

    Returns a list that gets populated as the test runs. Useful for
    verifying that the heartbeat URL contains the expected query params.
    """
    captured: list[str] = []

    def _get(url, timeout=None, **kwargs):  # noqa: ARG001
        captured.append(url)
        return _mock_response(
            "registream_update=false\nregistream_latest=\n"
        )

    monkeypatch.setattr("registream.updates.requests.get", _get)
    return captured
