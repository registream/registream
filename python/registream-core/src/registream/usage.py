"""Per-client usage logging: appends to ``usage_python.csv`` when enabled.

Schema mirrors the Stata writer (``_rs_usage.ado:_usage_init/_usage_log``):
``timestamp;user_id;platform;module;module_version;core_version;command_string;os;platform_version``.

When the on-disk header does not match the current schema, the old
file is rotated to ``usage_python.csv.old`` before the new header is
written (one-time schema migration on first run).
"""

from __future__ import annotations

import csv
import hashlib
import os
import platform
import secrets
import shutil
import socket
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from registream.config import load as load_config
from registream.dirs import get_registream_dir

__all__ = [
    "USAGE_FILENAME",
    "SALT_FILENAME",
    "USAGE_HEADER",
    "UsageStats",
    "usage_path",
    "init",
    "log",
    "stats",
    "compute_user_id",
]


USAGE_FILENAME = "usage_python.csv"
SALT_FILENAME = ".salt"
USAGE_HEADER: tuple[str, ...] = (
    "timestamp",
    "user_id",
    "platform",
    "module",
    "module_version",
    "core_version",
    "command_string",
    "os",
    "platform_version",
)


@dataclass
class UsageStats:
    user_id: str
    total_calls: int
    unique_users: int
    first_use: datetime | None
    last_use: datetime | None


def usage_path(directory: Path | str | None = None) -> Path:
    return _resolve_dir(directory) / USAGE_FILENAME


def init(directory: Path | str | None = None) -> None:
    """Ensure salt + usage CSV exist with the current header.

    If an existing file carries a pre-module-version header, it is
    rotated to ``.old`` and a fresh file with the current header is
    created. Mirrors the Stata rotation at ``_rs_usage.ado:48-61``.
    """
    dir_ = _resolve_dir(directory)
    dir_.mkdir(parents=True, exist_ok=True)

    _ensure_salt(dir_)

    path = dir_ / USAGE_FILENAME
    expected_header = list(USAGE_HEADER)

    if not path.exists():
        with path.open("w", encoding="utf-8", newline="") as fh:
            csv.writer(fh, delimiter=";").writerow(expected_header)
        return

    # Check the existing header: rotate if it doesn't match.
    try:
        with path.open("r", encoding="utf-8", newline="") as fh:
            reader = csv.reader(fh, delimiter=";")
            current_header = next(reader, [])
    except OSError:
        current_header = []

    if current_header != expected_header:
        try:
            shutil.copy2(path, path.with_suffix(".csv.old"))
        except OSError:
            pass
        with path.open("w", encoding="utf-8", newline="") as fh:
            csv.writer(fh, delimiter=";").writerow(expected_header)


def log(
    command: str,
    *,
    module: str,
    module_version: str,
    core_version: str,
    directory: Path | str | None = None,
) -> None:
    """Append a usage row to the CSV, if usage logging is enabled."""
    dir_ = _resolve_dir(directory)

    cfg = load_config(dir_)
    if not cfg.usage_logging:
        return

    init(dir_)

    user_id = compute_user_id(dir_)
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    os_name = platform.system()
    py_version = platform.python_version()

    # CSV-safety: strip semicolons and double quotes from command string.
    command_clean = command.replace(";", ",").replace('"', "'")

    path = dir_ / USAGE_FILENAME
    with path.open("a", encoding="utf-8", newline="") as fh:
        csv.writer(fh, delimiter=";").writerow(
            [
                timestamp,
                user_id,
                "python",
                module,
                module_version,
                core_version,
                command_clean,
                os_name,
                py_version,
            ]
        )


def stats(
    directory: Path | str | None = None,
    *,
    all_users: bool = False,
) -> UsageStats:
    dir_ = _resolve_dir(directory)
    path = dir_ / USAGE_FILENAME

    if not path.exists():
        user_id = compute_user_id(dir_) if (dir_ / SALT_FILENAME).exists() else ""
        return UsageStats(
            user_id=user_id,
            total_calls=0,
            unique_users=0,
            first_use=None,
            last_use=None,
        )

    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter=";")
        rows = list(reader)

    user_id = compute_user_id(dir_)
    unique_users = len({r["user_id"] for r in rows if r.get("user_id")})

    if not all_users:
        rows = [r for r in rows if r.get("user_id") == user_id]

    total_calls = len(rows)

    first_use: datetime | None = None
    last_use: datetime | None = None
    if rows:
        timestamps = [_parse_iso_timestamp(r["timestamp"]) for r in rows]
        valid = [t for t in timestamps if t is not None]
        if valid:
            first_use = min(valid)
            last_use = max(valid)

    return UsageStats(
        user_id=user_id,
        total_calls=total_calls,
        unique_users=unique_users,
        first_use=first_use,
        last_use=last_use,
    )


def compute_user_id(directory: Path | str | None = None) -> str:
    dir_ = _resolve_dir(directory)
    salt = _ensure_salt(dir_)
    combined = f"{_username()}{_hostname()}{salt}".encode("utf-8")
    return hashlib.sha256(combined).hexdigest()[:16]


def _ensure_salt(directory: Path | str | None = None) -> str:
    dir_ = _resolve_dir(directory)
    salt_path = dir_ / SALT_FILENAME
    if not salt_path.exists():
        dir_.mkdir(parents=True, exist_ok=True)
        salt_path.write_text(secrets.token_hex(32), encoding="utf-8")
    return salt_path.read_text(encoding="utf-8").strip()


def _username() -> str:
    try:
        return os.getlogin()
    except (OSError, AttributeError):
        return os.environ.get("USER") or os.environ.get("USERNAME") or "unknown"


def _hostname() -> str:
    try:
        return socket.gethostname()
    except OSError:
        return "unknown"


def _parse_iso_timestamp(s: str) -> datetime | None:
    if not s:
        return None
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def _resolve_dir(directory: Path | str | None) -> Path:
    if directory is None:
        return get_registream_dir()
    return Path(directory).expanduser()
