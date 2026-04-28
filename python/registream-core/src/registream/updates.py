"""HTTP heartbeat / update check. Mirrors Stata ``_rs_updates``.

Hits ``<api_host>/api/v1/heartbeat`` with the current versions, returns
parsed update info. Caches results via the ``last_update_check`` config
field for 24 hours.

The endpoint format and response parsing mirror the Stata side line for
line so a single server can serve both clients, with ``?format=stata``
selecting the key=value text response and ``?platform=python`` tagging
the telemetry row.

The Python version is **non-interactive**: ``update_package()`` returns a
:class:`HeartbeatResult` and the caller decides what to do (display the
banner, run ``pip install --upgrade``, etc.). The Stata side runs an
interactive ``net install`` flow inline; that is a Stata-specific UX.
"""

from __future__ import annotations

import logging
import platform as _platform
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal
from urllib.parse import urlencode

import requests

from registream.config import load as load_config
from registream.config import save as save_config
from registream.dirs import get_registream_dir
from registream.usage import compute_user_id
from registream.utils import get_api_host

__all__ = [
    "HEARTBEAT_PATH",
    "CACHE_HOURS",
    "NETWORK_TIMEOUT_SECONDS",
    "HeartbeatResult",
    "check_package",
    "check_pypi_updates",
    "send_heartbeat",
    "show_notification",
    "compare_versions",
    "update_package",
]


# The heartbeat endpoint on registream.org is client-agnostic: it accepts
# `?platform=python` for telemetry classification and `?format=stata` to
# select the plain-text key=value response format. Verified against
# `registream.org/app/api/v1/versions.py::heartbeat`.
HEARTBEAT_PATH = "/api/v1/heartbeat"
CACHE_HOURS = 24
NETWORK_TIMEOUT_SECONDS = 10

_log = logging.getLogger("registream.updates")


@dataclass
class HeartbeatResult:
    """Result of a heartbeat / update check.

    ``reason`` describes how the result was produced:

    - ``success``         : network call succeeded, ``update_available`` is fresh
    - ``cached``          : returned from the 24-hour cache (no network)
    - ``internet_disabled``: ``internet_access`` is False in the config
    - ``network_error``   : the HTTP call failed (timeout, DNS, 5xx, …)
    """

    update_available: bool = False
    latest_version: str = ""
    autolabel_update: bool = False
    autolabel_latest: str = ""
    datamirror_update: bool = False
    datamirror_latest: str = ""
    reason: str = "success"


# ─── Public API ────────────────────────────────────────────────────────────────


def _installed_version(pkg: str) -> str | None:
    """Return the installed version of ``pkg``, or None if not installed."""
    try:
        from importlib.metadata import PackageNotFoundError, version as _v
        try:
            return _v(pkg)
        except PackageNotFoundError:
            return None
    except Exception:
        return None


def check_package(
    version: str,
    directory: Path | str | None = None,
) -> HeartbeatResult:
    """Force an immediate update check (interactive ``update`` command).

    Mirrors ``_rs_updates check_package``. Expires the 24-hour cache so the
    next heartbeat actually hits the network. Returns a
    :class:`HeartbeatResult`.

    Autodetects installed RegiStream modules (``registream-autolabel``,
    ``registream-datamirror``) and includes them in the heartbeat so the
    server can report per-module update availability.
    """
    dir_ = _resolve_dir(directory)
    cfg = load_config(dir_)

    if not cfg.internet_access:
        return HeartbeatResult(reason="internet_disabled", latest_version="")

    # Expire the cache so send_heartbeat actually fetches.
    cfg.last_update_check = datetime(1970, 1, 1, tzinfo=timezone.utc)
    try:
        save_config(cfg, dir_)
    except OSError:
        pass  # Read-only filesystem; we'll still try the network.

    return send_heartbeat(
        version,
        command="registream update",
        directory=dir_,
        autolabel_version=_installed_version("registream-autolabel"),
        datamirror_version=_installed_version("registream-datamirror"),
    )


def send_heartbeat(
    version: str,
    command: str,
    directory: Path | str | None = None,
    *,
    autolabel_version: str | None = None,
    datamirror_version: str | None = None,
) -> HeartbeatResult:
    """Send a heartbeat (telemetry + update check), respecting cache.

    Mirrors ``_rs_updates send_heartbeat``. Behaviour:

    - If ``internet_access`` is False, returns immediately with
      ``reason="internet_disabled"``.
    - If ``auto_update_check`` is True AND the cache is fresh (< 24h),
      returns the cached result with ``reason="cached"`` without hitting
      the network.
    - If neither telemetry nor update checking is enabled, exits early
      with ``reason="success"``.
    - Otherwise hits the heartbeat endpoint with query params, parses the
      response, and updates the cache fields in the config file.
    - On network errors, returns ``reason="network_error"``.
    """
    dir_ = _resolve_dir(directory)
    cfg = load_config(dir_)

    if not cfg.internet_access:
        return HeartbeatResult(reason="internet_disabled")

    # 24-hour cache check.
    if cfg.auto_update_check and cfg.last_update_check is not None:
        now = datetime.now(timezone.utc)
        last = cfg.last_update_check
        if last.tzinfo is None:
            last = last.replace(tzinfo=timezone.utc)
        if now - last < timedelta(hours=CACHE_HOURS):
            # Rehydrate per-module cache fields so the caller can read them
            # without issuing a network call. Matches Stata's cache-hit path
            # in _upd_send_heartbeat.
            return HeartbeatResult(
                update_available=cfg.update_available,
                latest_version=cfg.latest_version,
                autolabel_update=cfg.autolabel_update_available,
                autolabel_latest=cfg.autolabel_latest_version,
                datamirror_update=cfg.datamirror_update_available,
                datamirror_latest=cfg.datamirror_latest_version,
                reason="cached",
            )

    # If neither telemetry nor update checking is enabled, no work to do.
    if not cfg.telemetry_enabled and not cfg.auto_update_check:
        return HeartbeatResult(reason="success")

    # Try POST with batch usage data if telemetry is enabled and there
    # are usage rows since the last heartbeat. Falls back to GET if the
    # server doesn't support POST yet (405) or on any error.
    usage_rows = (
        _read_usage_since(dir_, cfg.last_update_check)
        if cfg.telemetry_enabled
        else []
    )

    try:
        if usage_rows:
            # POST batch usage: sends all commands since last heartbeat.
            # Each usage row is self-contained (all CSV columns). The
            # top-level fields are only for the version-check response.
            payload: dict = {
                "format": "stata",
                "registream": version,
                "usage": usage_rows,
            }
            if autolabel_version is not None:
                payload["autolabel"] = autolabel_version
            if datamirror_version is not None:
                payload["datamirror"] = datamirror_version

            response = requests.post(
                f"{get_api_host()}{HEARTBEAT_PATH}",
                json=payload,
                timeout=NETWORK_TIMEOUT_SECONDS,
            )
            if response.status_code == 405:
                # Server doesn't support POST yet; fall back to GET
                url = _build_heartbeat_url(
                    version=version,
                    command=command,
                    cfg=cfg,
                    directory=dir_,
                    autolabel_version=autolabel_version,
                    datamirror_version=datamirror_version,
                )
                response = requests.get(url, timeout=NETWORK_TIMEOUT_SECONDS)
            response.raise_for_status()
        else:
            # GET: no batch usage to send
            url = _build_heartbeat_url(
                version=version,
                command=command,
                cfg=cfg,
                directory=dir_,
                autolabel_version=autolabel_version,
                datamirror_version=datamirror_version,
            )
            response = requests.get(url, timeout=NETWORK_TIMEOUT_SECONDS)
            response.raise_for_status()
    except requests.RequestException as exc:
        _log.warning("Heartbeat network error: %s", exc)
        return HeartbeatResult(reason="network_error")

    result = _parse_heartbeat_response(response.text)

    # Persist cache fields.
    cfg.last_update_check = datetime.now(timezone.utc)
    cfg.update_available = result.update_available
    cfg.latest_version = result.latest_version
    # Per-module fields: only overwrite when we asked the server about that
    # module (i.e., a version was sent). Preserves prior cached state for
    # untouched modules. Matches Stata policy in _upd_send_heartbeat.
    if autolabel_version is not None:
        cfg.autolabel_update_available = result.autolabel_update
        cfg.autolabel_latest_version = result.autolabel_latest
    if datamirror_version is not None:
        cfg.datamirror_update_available = result.datamirror_update
        cfg.datamirror_latest_version = result.datamirror_latest
    try:
        save_config(cfg, dir_)
    except OSError:
        # Read-only filesystem; cache won't persist but the result is still
        # valid for this process.
        pass

    return result


def show_notification(
    current_version: str,
    result: HeartbeatResult,
    scope: Literal["core", "autolabel", "datamirror"] = "core",
) -> str:
    """Return a formatted update banner if an update is available, else ``""``.

    Mirrors ``_rs_updates show_notification``. Caller is responsible for
    printing the result; this function never writes to stdout.

    ``scope`` applies the 2026-04-17 notification policy: core always shows,
    siblings suppressed. ``scope="core"`` is the meta-command context
    (``rs_update_package()`` / ``registream update``) and surfaces every
    module; module-specific callers pass their own scope to avoid
    interrupting the user with unrelated-module banners.
    """
    lines: list[str] = []

    # Core banner: always shown when an update is available.
    if result.update_available:
        lines.extend(
            [
                "",
                "─" * 60,
                "A new version of registream is available!",
                f"  Current version:  {current_version}",
                f"  Latest version:   {result.latest_version}",
                "",
                "To update, run: pip install --upgrade registream",
                "─" * 60,
                "",
            ]
        )

    if (
        scope in ("core", "autolabel")
        and result.autolabel_update
        and result.autolabel_latest
    ):
        lines.extend(
            [
                "",
                "─" * 60,
                "A new version of registream-autolabel is available!",
                f"  Latest version:   {result.autolabel_latest}",
                "",
                "To update, run: pip install --upgrade registream-autolabel",
                "─" * 60,
                "",
            ]
        )

    if (
        scope in ("core", "datamirror")
        and result.datamirror_update
        and result.datamirror_latest
    ):
        lines.extend(
            [
                "",
                "─" * 60,
                "A new version of registream-datamirror is available!",
                f"  Latest version:   {result.datamirror_latest}",
                "",
                "To update, run: pip install --upgrade registream-datamirror",
                "─" * 60,
                "",
            ]
        )

    return "\n".join(lines)


def compare_versions(current: str, latest: str) -> bool:
    """Return ``True`` if ``latest`` is newer than ``current`` (semver compare).

    Strips pre-release / build metadata (anything after ``-`` or ``+``) and
    compares the remaining ``major.minor.patch`` tuple.
    """
    try:
        return _parse_version(latest) > _parse_version(current)
    except ValueError:
        return False


def check_pypi_updates() -> list[tuple[str, str, str]]:
    """Check PyPI for newer versions of installed registream packages.

    Returns a list of ``(package_name, current_version, latest_version)``
    tuples for packages that have updates available. Stateless; no
    caching; the caller gates how often this runs (e.g., only when the
    heartbeat fires fresh).

    This is the Pythonic approach to update checks: PyPI is the
    authoritative source for package versions. The heartbeat endpoint
    is for telemetry only.
    """
    from importlib.metadata import PackageNotFoundError
    from importlib.metadata import version as get_version

    updates: list[tuple[str, str, str]] = []
    for pkg in ("registream-core", "registream-autolabel"):
        try:
            current = get_version(pkg)
        except PackageNotFoundError:
            continue
        try:
            resp = requests.get(
                f"https://pypi.org/pypi/{pkg}/json",
                timeout=NETWORK_TIMEOUT_SECONDS,
            )
            resp.raise_for_status()
            latest = resp.json()["info"]["version"]
            if compare_versions(current, latest):
                updates.append((pkg, current, latest))
        except Exception:
            continue
    return updates


def update_package(
    version: str | None = None,
    directory: Path | str | None = None,
) -> HeartbeatResult:
    """Check for an updated registream-core package on PyPI.

    Returns a :class:`HeartbeatResult` describing what was found. Does NOT
    actually install anything; that's the user's job (``pip install
    --upgrade registream``). The Stata version uses an interactive
    ``net install`` flow, but the Python equivalent is non-interactive:
    callers display the result and let the user run pip themselves.
    """
    if version is None:
        version = _installed_core_version()
    return check_package(version, directory=directory)


# ─── Internal helpers ──────────────────────────────────────────────────────────


def _build_heartbeat_url(
    *,
    version: str,
    command: str,
    cfg: object,  # registream.config.Config; typed as object to avoid circular imports
    directory: Path,
    autolabel_version: str | None,
    datamirror_version: str | None,
) -> str:
    """Construct the heartbeat URL with query parameters.

    Same parameter set as Stata's heartbeat URL, just at the parallel
    Python endpoint.
    """
    params: dict[str, str] = {
        "platform": "python",   # telemetry classification: this is a Python client
        "registream": version,
        "format": "stata",      # response format selector: plain text key=value
        # NOTE: `format=stata` is the server-side flag for the plain-text
        # response format, not a claim that we are a Stata client. The
        # `platform=python` param is what tells the server we are Python
        # for telemetry purposes.
    }

    # Telemetry-only parameters (only sent if telemetry is enabled)
    if getattr(cfg, "telemetry_enabled", False):
        params["user_id"] = compute_user_id(directory)
        params["command"] = command
        params["os"] = _platform.system()
        params["platform_version"] = _platform.python_version()
        params["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    if autolabel_version is not None:
        params["autolabel"] = autolabel_version
    if datamirror_version is not None:
        params["datamirror"] = datamirror_version

    return f"{get_api_host()}{HEARTBEAT_PATH}?{urlencode(params)}"


def _parse_heartbeat_response(text: str) -> HeartbeatResult:
    """Parse a key=value response body into a :class:`HeartbeatResult`.

    Same wire format as the Stata client expects::

        registream_update=true
        registream_latest=3.1.0
        autolabel_update=false
        autolabel_latest=
        datamirror_update=false
        datamirror_latest=
    """
    result = HeartbeatResult()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()

        if key == "registream_update":
            result.update_available = value.lower() == "true"
        elif key == "registream_latest":
            result.latest_version = value
        elif key == "autolabel_update":
            result.autolabel_update = value.lower() == "true"
        elif key == "autolabel_latest":
            result.autolabel_latest = value
        elif key == "datamirror_update":
            result.datamirror_update = value.lower() == "true"
        elif key == "datamirror_latest":
            result.datamirror_latest = value

    return result


def _parse_version(s: str) -> tuple[int, ...]:
    """Parse ``X.Y.Z[-suffix][+build]`` into a tuple of ints, ignoring suffixes."""
    s = s.split("-", 1)[0].split("+", 1)[0]
    parts = s.split(".")
    return tuple(int(p) for p in parts)


def _installed_core_version() -> str:
    """Return the installed registream-core version, or 'unknown' if not found."""
    from importlib.metadata import PackageNotFoundError, version as get_version

    try:
        return get_version("registream-core")
    except PackageNotFoundError:
        return "unknown"


def _read_usage_since(
    directory: Path, since: datetime | None
) -> list[dict[str, str]]:
    """Read usage_python.csv rows since ``since``, returning command+timestamp pairs.

    Used by :func:`send_heartbeat` to batch-send all usage data since the
    last heartbeat. Returns a list of ``{"ts": ..., "cmd": ...}`` dicts
    that the server stores as individual ``TelemetryEvent`` rows.
    """
    import csv

    from registream.usage import USAGE_FILENAME

    usage_path = directory / USAGE_FILENAME
    if not usage_path.exists():
        return []

    rows: list[dict[str, str]] = []
    try:
        with usage_path.open("r", encoding="utf-8") as fh:
            reader = csv.DictReader(fh, delimiter=";")
            for row in reader:
                if since is not None:
                    try:
                        ts_str = row.get("timestamp", "")
                        row_time = datetime.strptime(
                            ts_str, "%Y-%m-%dT%H:%M:%SZ"
                        ).replace(tzinfo=timezone.utc)
                        if row_time <= since:
                            continue
                    except (ValueError, TypeError):
                        pass  # include rows with unparseable timestamps
                # Send the full row (same columns as the CSV). This way
                # the server receives the same format whether it comes
                # from a heartbeat POST or a bulk CSV upload (e.g., from
                # SCB's MONA server via emailed usage files).
                rows.append(
                    {
                        "timestamp": row.get("timestamp", ""),
                        "user_id": row.get("user_id", ""),
                        "platform": row.get("platform", ""),
                        "version": row.get("version", ""),
                        "command_string": row.get("command_string", ""),
                        "os": row.get("os", ""),
                        "platform_version": row.get("platform_version", ""),
                    }
                )
    except Exception:
        pass  # non-fatal, can't read CSV, skip batch

    return rows


def _resolve_dir(directory: Path | str | None) -> Path:
    if directory is None:
        return get_registream_dir()
    return Path(directory).expanduser()
