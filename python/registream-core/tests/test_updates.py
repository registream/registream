"""Unit tests for registream.updates."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from registream.config import Config
from registream.config import load as load_config
from registream.config import save as save_config
from registream.updates import (
    HEARTBEAT_PATH,
    HeartbeatResult,
    _installed_version,
    _parse_heartbeat_response,
    _read_usage_since,
    check_package,
    check_pypi_updates,
    compare_versions,
    send_heartbeat,
    show_notification,
    update_package,
)


# ─── HeartbeatResult dataclass ─────────────────────────────────────────────────


def test_heartbeat_result_defaults() -> None:
    r = HeartbeatResult()
    assert r.update_available is False
    assert r.latest_version == ""
    assert r.reason == "success"


# ─── compare_versions ─────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("current", "latest", "expected"),
    [
        ("1.0.0", "2.0.0", True),       # major
        ("1.0.0", "1.1.0", True),       # minor
        ("1.0.0", "1.0.1", True),       # patch
        ("2.0.0", "1.9.9", False),      # downgrade
        ("3.0.0", "3.0.0", False),      # equal
        ("3.0.0a1", "3.0.0", False),    # pre-release of same final = equal after strip
        ("3.0.0", "3.0.1+build", True), # build metadata stripped
    ],
)
def test_compare_versions(current: str, latest: str, expected: bool) -> None:
    assert compare_versions(current, latest) is expected


def test_compare_versions_invalid_returns_false() -> None:
    assert compare_versions("not.a.version", "1.0.0") is False


# ─── _parse_heartbeat_response ─────────────────────────────────────────────────


def test_parse_response_update_available() -> None:
    body = "registream_update=true\nregistream_latest=99.0.0\n"
    result = _parse_heartbeat_response(body)
    assert result.update_available is True
    assert result.latest_version == "99.0.0"


def test_parse_response_no_update() -> None:
    body = "registream_update=false\nregistream_latest=\n"
    result = _parse_heartbeat_response(body)
    assert result.update_available is False
    assert result.latest_version == ""


def test_parse_response_with_autolabel() -> None:
    body = (
        "registream_update=false\n"
        "autolabel_update=true\n"
        "autolabel_latest=3.5.0\n"
    )
    result = _parse_heartbeat_response(body)
    assert result.autolabel_update is True
    assert result.autolabel_latest == "3.5.0"


def test_parse_response_handles_blank_lines() -> None:
    body = "\nregistream_update=true\n\nregistream_latest=2.0.0\n"
    result = _parse_heartbeat_response(body)
    assert result.update_available is True


def test_parse_response_with_datamirror() -> None:
    body = "datamirror_update=true\ndatamirror_latest=1.5.0\n"
    result = _parse_heartbeat_response(body)
    assert result.datamirror_update is True
    assert result.datamirror_latest == "1.5.0"


# ─── send_heartbeat: internet_disabled ───────────────────────────────────────


def test_send_heartbeat_returns_internet_disabled_when_offline(tmp_path: Path) -> None:
    save_config(Config(internet_access=False), tmp_path)
    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "internet_disabled"


# ─── send_heartbeat: cached ──────────────────────────────────────────────────


def test_send_heartbeat_uses_fresh_cache(tmp_path: Path) -> None:
    """If last_update_check is recent, return cached without hitting network."""
    cfg = Config(
        last_update_check=datetime.now(timezone.utc) - timedelta(hours=1),
        update_available=True,
        latest_version="42.0.0",
    )
    save_config(cfg, tmp_path)

    # No mock; if network is hit, the call would fail or hang
    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "cached"
    assert result.update_available is True
    assert result.latest_version == "42.0.0"


# ─── send_heartbeat: early exit when nothing to do ───────────────────────────


def test_send_heartbeat_early_exit_when_nothing_enabled(tmp_path: Path) -> None:
    cfg = Config(
        telemetry_enabled=False,
        auto_update_check=False,
        last_update_check=None,
    )
    save_config(cfg, tmp_path)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "success"
    assert result.update_available is False


# ─── send_heartbeat: successful network call ─────────────────────────────────


def test_send_heartbeat_success(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    save_config(Config(last_update_check=None), tmp_path)
    result = send_heartbeat("3.0.0", "test", tmp_path)

    assert result.reason == "success"
    assert result.update_available is True
    assert result.latest_version == "99.0.0"


def test_send_heartbeat_persists_cache_on_success(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    save_config(Config(last_update_check=None), tmp_path)
    send_heartbeat("3.0.0", "test", tmp_path)

    cfg = load_config(tmp_path)
    assert cfg.last_update_check is not None
    assert cfg.update_available is True
    assert cfg.latest_version == "99.0.0"


# ─── send_heartbeat: network error ───────────────────────────────────────────


def test_send_heartbeat_network_error(
    tmp_path: Path,
    mock_network_error: None,
) -> None:
    save_config(Config(last_update_check=None), tmp_path)
    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "network_error"


# ─── send_heartbeat: URL contents ────────────────────────────────────────────


def test_send_heartbeat_url_contains_expected_params(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
) -> None:
    save_config(
        Config(last_update_check=None, telemetry_enabled=True),
        tmp_path,
    )
    send_heartbeat("3.0.0", "registream test", tmp_path)

    assert len(captured_heartbeat_url) == 1
    url = captured_heartbeat_url[0]

    assert HEARTBEAT_PATH in url
    assert "platform=python" in url
    assert "registream=3.0.0" in url
    assert "format=stata" in url  # plain-text response format selector
    assert "user_id=" in url  # telemetry on → user_id sent
    assert "command=" in url


def test_send_heartbeat_url_excludes_user_id_when_telemetry_off(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
) -> None:
    save_config(
        Config(last_update_check=None, telemetry_enabled=False, auto_update_check=True),
        tmp_path,
    )
    send_heartbeat("3.0.0", "test", tmp_path)

    assert len(captured_heartbeat_url) == 1
    url = captured_heartbeat_url[0]
    assert "user_id" not in url


def test_send_heartbeat_url_includes_autolabel_version(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
) -> None:
    save_config(Config(last_update_check=None), tmp_path)
    send_heartbeat("3.0.0", "test", tmp_path, autolabel_version="3.0.0")

    url = captured_heartbeat_url[0]
    assert "autolabel=3.0.0" in url


# ─── check_package ────────────────────────────────────────────────────────────


def test_check_package_internet_disabled(tmp_path: Path) -> None:
    save_config(Config(internet_access=False), tmp_path)
    result = check_package("3.0.0", tmp_path)
    assert result.reason == "internet_disabled"


def test_check_package_expires_cache_then_fetches(
    tmp_path: Path,
    mock_heartbeat_success: None,
) -> None:
    """check_package should ignore the cache and force a fresh fetch."""
    cfg = Config(
        last_update_check=datetime.now(timezone.utc),  # very fresh
        update_available=False,
        latest_version="",
    )
    save_config(cfg, tmp_path)

    result = check_package("3.0.0", tmp_path)
    # If cache had been honored, reason would be "cached"
    assert result.reason == "success"
    assert result.update_available is True
    assert result.latest_version == "99.0.0"


# ─── _installed_version ──────────────────────────────────────────────────────


def test_installed_version_returns_string_for_installed_pkg() -> None:
    """Any module that is currently importable returns its declared version."""
    v = _installed_version("registream-core")
    assert isinstance(v, str) and v  # non-empty string


def test_installed_version_returns_none_for_missing_pkg() -> None:
    assert _installed_version("definitely-not-a-real-package-xyz-123") is None


# ─── check_package: module-awareness (autolabel / datamirror) ───────────────


def test_check_package_includes_autolabel_version_when_installed(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """check_package must auto-discover registream-autolabel and pass its
    version so the server can report per-module update availability."""
    save_config(Config(last_update_check=None), tmp_path)

    def _fake_installed(pkg: str) -> str | None:
        return {"registream-autolabel": "3.0.1"}.get(pkg)

    monkeypatch.setattr("registream.updates._installed_version", _fake_installed)

    check_package("3.0.0", tmp_path)

    assert len(captured_heartbeat_url) == 1
    url = captured_heartbeat_url[0]
    assert "autolabel=3.0.1" in url
    assert "datamirror=" not in url  # not installed → omitted


def test_check_package_includes_both_modules_when_installed(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    save_config(Config(last_update_check=None), tmp_path)

    def _fake_installed(pkg: str) -> str | None:
        return {
            "registream-autolabel": "3.0.0",
            "registream-datamirror": "1.2.3",
        }.get(pkg)

    monkeypatch.setattr("registream.updates._installed_version", _fake_installed)

    check_package("3.0.0", tmp_path)

    url = captured_heartbeat_url[0]
    assert "autolabel=3.0.0" in url
    assert "datamirror=1.2.3" in url


def test_check_package_omits_modules_when_not_installed(
    tmp_path: Path,
    captured_heartbeat_url: list[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """No autolabel/datamirror params when neither is installed."""
    save_config(Config(last_update_check=None), tmp_path)

    monkeypatch.setattr(
        "registream.updates._installed_version", lambda pkg: None
    )

    check_package("3.0.0", tmp_path)

    url = captured_heartbeat_url[0]
    assert "autolabel=" not in url
    assert "datamirror=" not in url
    # Core version is still there
    assert "registream=3.0.0" in url


# ─── show_notification ────────────────────────────────────────────────────────


def test_show_notification_empty_when_no_update() -> None:
    result = HeartbeatResult(update_available=False)
    assert show_notification("3.0.0", result) == ""


def test_show_notification_includes_versions_when_update_available() -> None:
    result = HeartbeatResult(update_available=True, latest_version="99.0.0")
    text = show_notification("3.0.0", result)
    assert "registream" in text
    assert "3.0.0" in text
    assert "99.0.0" in text
    assert "pip install --upgrade registream" in text


def test_show_notification_autolabel_section() -> None:
    result = HeartbeatResult(autolabel_update=True, autolabel_latest="3.5.0")
    text = show_notification("3.0.0", result)
    assert "registream-autolabel" in text
    assert "3.5.0" in text


def test_show_notification_datamirror_section() -> None:
    result = HeartbeatResult(datamirror_update=True, datamirror_latest="1.2.0")
    text = show_notification("3.0.0", result)
    assert "registream-datamirror" in text
    assert "1.2.0" in text


def test_show_notification_scope_autolabel_hides_datamirror_banner() -> None:
    """scope='autolabel' suppresses the datamirror banner (2026-04-17 policy)."""
    result = HeartbeatResult(
        autolabel_update=True,
        autolabel_latest="3.5.0",
        datamirror_update=True,
        datamirror_latest="1.2.0",
    )
    text = show_notification("3.0.0", result, scope="autolabel")
    assert "registream-autolabel" in text
    assert "registream-datamirror" not in text


def test_show_notification_scope_datamirror_hides_autolabel_banner() -> None:
    """scope='datamirror' suppresses the autolabel banner."""
    result = HeartbeatResult(
        autolabel_update=True,
        autolabel_latest="3.5.0",
        datamirror_update=True,
        datamirror_latest="1.2.0",
    )
    text = show_notification("3.0.0", result, scope="datamirror")
    assert "registream-datamirror" in text
    assert "registream-autolabel" not in text


def test_show_notification_scope_core_shows_all_banners() -> None:
    """scope='core' (default) shows every module's banner."""
    result = HeartbeatResult(
        update_available=True,
        latest_version="99.0.0",
        autolabel_update=True,
        autolabel_latest="3.5.0",
        datamirror_update=True,
        datamirror_latest="1.2.0",
    )
    text = show_notification("3.0.0", result, scope="core")
    assert "registream is available" in text
    assert "registream-autolabel" in text
    assert "registream-datamirror" in text


def test_send_heartbeat_cache_hit_rehydrates_per_module_fields(
    tmp_path: Path,
) -> None:
    """Cache-hit branch returns per-module cached state, not just core.

    Guards against Gap 2: prior implementation only repopulated core
    fields on cache-hit, leaving autolabel/datamirror updates invisible
    for up to 24 hours when the first heartbeat of the day was scoped
    to a different module.
    """
    # Seed a fresh cache with per-module update state already persisted.
    cfg = Config(
        last_update_check=datetime.now(timezone.utc),
        update_available=False,
        autolabel_update_available=True,
        autolabel_latest_version="3.5.0",
        datamirror_update_available=True,
        datamirror_latest_version="1.2.0",
    )
    save_config(cfg, tmp_path)

    result = send_heartbeat("3.0.0", command="registream info", directory=tmp_path)

    assert result.reason == "cached"
    assert result.autolabel_update is True
    assert result.autolabel_latest == "3.5.0"
    assert result.datamirror_update is True
    assert result.datamirror_latest == "1.2.0"


# ─── check_pypi_updates ──────────────────────────────────────────────────────


def test_check_pypi_updates_returns_empty_when_up_to_date(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """If PyPI has the same version, return empty list."""
    import json

    from importlib.metadata import version as get_version

    current = get_version("registream-core")

    def _get(url, timeout=None, **kwargs):
        from unittest.mock import MagicMock

        resp = MagicMock()
        resp.status_code = 200
        resp.raise_for_status = MagicMock()
        resp.json.return_value = {"info": {"version": current}}
        return resp

    monkeypatch.setattr("registream.updates.requests.get", _get)

    updates = check_pypi_updates()
    core_updates = [u for u in updates if u[0] == "registream-core"]
    assert core_updates == []


def test_check_pypi_updates_detects_newer_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """If PyPI has a newer version, include it in the result."""

    def _get(url, timeout=None, **kwargs):
        from unittest.mock import MagicMock

        resp = MagicMock()
        resp.status_code = 200
        resp.raise_for_status = MagicMock()
        resp.json.return_value = {"info": {"version": "99.0.0"}}
        return resp

    monkeypatch.setattr("registream.updates.requests.get", _get)

    updates = check_pypi_updates()
    assert len(updates) > 0
    pkg, current, latest = updates[0]
    assert latest == "99.0.0"


def test_check_pypi_updates_handles_network_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Network errors are swallowed; return empty list."""

    def _get(url, timeout=None, **kwargs):
        raise requests.ConnectionError("simulated")

    monkeypatch.setattr("registream.updates.requests.get", _get)

    updates = check_pypi_updates()
    assert updates == []


def test_check_pypi_updates_scope_excludes_datamirror(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Policy: check_pypi_updates() is invoked from the autolabel context
    (post-heartbeat banner) and must never surface datamirror updates;
    datamirror notifications are the job of datamirror-triggered
    heartbeats and the explicit `registream update` meta-command.

    Lock by asserting the set of PyPI URLs this function polls."""
    queried: list[str] = []

    def _get(url, timeout=None, **kwargs):
        queried.append(url)
        resp = MagicMock()
        resp.status_code = 200
        resp.raise_for_status = MagicMock()
        resp.json.return_value = {"info": {"version": "0.0.0"}}
        return resp

    # Pretend both context-scoped packages are installed so the PyPI poll
    # actually fires for each. In the core test venv, registream-autolabel
    # may not be installed as a sibling; mock the importlib lookup.
    def _fake_version(pkg: str) -> str:
        return {
            "registream-core": "3.0.0",
            "registream-autolabel": "3.0.0",
        }.get(pkg, "unknown")

    monkeypatch.setattr("registream.updates.requests.get", _get)
    monkeypatch.setattr("importlib.metadata.version", _fake_version)
    check_pypi_updates()

    # Exactly the two context-scoped packages are polled.
    joined = " ".join(queried)
    assert "registream-core" in joined
    assert "registream-autolabel" in joined
    assert "datamirror" not in joined


# ─── _read_usage_since ───────────────────────────────────────────────────────


def test_read_usage_since_returns_all_rows_when_no_since(tmp_path: Path) -> None:
    from registream.usage import log as usage_log

    save_config(Config(usage_logging=True), tmp_path)
    usage_log("autolabel domain=scb lang=eng", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    usage_log("lookup kon domain=scb", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    rows = _read_usage_since(tmp_path, since=None)
    assert len(rows) == 2
    assert rows[0]["command_string"] == "autolabel domain=scb lang=eng"
    assert rows[1]["command_string"] == "lookup kon domain=scb"
    # All CSV columns present
    assert rows[0]["platform"] == "python"
    assert rows[0]["user_id"]
    assert rows[0]["os"]
    assert rows[0]["timestamp"]


def test_read_usage_since_filters_by_timestamp(tmp_path: Path) -> None:
    """Rows written before `since` are excluded, rows after are included."""
    import csv

    from registream.usage import USAGE_FILENAME, USAGE_HEADER, init as usage_init

    save_config(Config(usage_logging=True), tmp_path)
    usage_init(tmp_path)

    # Write rows with explicit timestamps (avoids clock-precision issues)
    path = tmp_path / USAGE_FILENAME
    with path.open("a", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(["2026-04-10T10:00:00Z", "u1", "python", "autolabel", "3.0.0", "3.0.0", "old_command", "Darwin", "3.13"])
        writer.writerow(["2026-04-10T12:00:00Z", "u1", "python", "autolabel", "3.0.0", "3.0.0", "new_command", "Darwin", "3.13"])

    cutoff = datetime(2026, 4, 10, 11, 0, 0, tzinfo=timezone.utc)
    rows = _read_usage_since(tmp_path, since=cutoff)
    assert len(rows) == 1
    assert rows[0]["command_string"] == "new_command"


def test_read_usage_since_empty_file(tmp_path: Path) -> None:
    rows = _read_usage_since(tmp_path, since=None)
    assert rows == []


# ─── send_heartbeat: batch POST ────────────────────────────────────────────


def test_send_heartbeat_posts_batch_usage(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """When telemetry is enabled and usage rows exist, send_heartbeat POSTs."""
    from registream.usage import log as usage_log

    save_config(
        Config(telemetry_enabled=True, last_update_check=None, usage_logging=True),
        tmp_path,
    )
    usage_log("autolabel domain=scb lang=eng", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    usage_log("lookup kon", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    posted = {}

    def _post(url, json=None, timeout=None, **kwargs):
        posted["url"] = url
        posted["json"] = json
        resp = MagicMock()
        resp.status_code = 200
        resp.text = "registream_update=false\nregistream_latest=\n"
        resp.raise_for_status = MagicMock()
        return resp

    monkeypatch.setattr("registream.updates.requests.post", _post)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "success"

    # Verify POST was called with batch usage
    assert "json" in posted
    usage = posted["json"]["usage"]
    assert len(usage) == 2
    assert usage[0]["command_string"] == "autolabel domain=scb lang=eng"
    assert usage[1]["command_string"] == "lookup kon"
    # Self-contained rows
    assert usage[0]["platform"] == "python"
    assert usage[0]["user_id"]


def test_send_heartbeat_falls_back_to_get_on_405(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """If server returns 405 on POST, fall back to GET."""
    from registream.usage import log as usage_log

    save_config(
        Config(telemetry_enabled=True, last_update_check=None, usage_logging=True),
        tmp_path,
    )
    usage_log("autolabel domain=scb", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    def _post(url, json=None, timeout=None, **kwargs):
        resp = MagicMock()
        resp.status_code = 405
        return resp

    def _get(url, timeout=None, **kwargs):
        resp = MagicMock()
        resp.status_code = 200
        resp.text = "registream_update=false\nregistream_latest=\n"
        resp.raise_for_status = MagicMock()
        return resp

    monkeypatch.setattr("registream.updates.requests.post", _post)
    monkeypatch.setattr("registream.updates.requests.get", _get)

    result = send_heartbeat("3.0.0", "test", tmp_path)
    assert result.reason == "success"


# ─── update_package ──────────────────────────────────────────────────────────


def test_update_package_uses_installed_version_when_omitted(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """If version arg is omitted, update_package() reads it from importlib.metadata."""
    save_config(Config(last_update_check=None), tmp_path)
    result = update_package(directory=tmp_path)
    assert isinstance(result, HeartbeatResult)
