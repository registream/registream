"""Unit tests for registream.usage."""

from __future__ import annotations

import csv
from pathlib import Path

from registream.config import Config
from registream.config import save as save_config
from registream.usage import (
    SALT_FILENAME,
    USAGE_FILENAME,
    USAGE_HEADER,
    UsageStats,
    compute_user_id,
    init,
    log,
    stats,
    usage_path,
)


# ─── usage_path ────────────────────────────────────────────────────────────────


def test_usage_path_default(isolated_dir: Path) -> None:
    assert usage_path() == isolated_dir / USAGE_FILENAME


def test_usage_path_filename_is_python(tmp_path: Path) -> None:
    """Per-client convention: usage_python.csv, not usage_stata.csv."""
    assert usage_path(tmp_path).name == "usage_python.csv"


# ─── init() ────────────────────────────────────────────────────────────────────


def test_init_creates_salt_file(tmp_path: Path) -> None:
    init(tmp_path)
    assert (tmp_path / SALT_FILENAME).exists()


def test_init_creates_usage_file_with_header(tmp_path: Path) -> None:
    init(tmp_path)
    path = tmp_path / USAGE_FILENAME
    assert path.exists()

    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh, delimiter=";")
        header = next(reader)

    assert tuple(header) == USAGE_HEADER


def test_init_idempotent(tmp_path: Path) -> None:
    init(tmp_path)
    salt1 = (tmp_path / SALT_FILENAME).read_text()

    init(tmp_path)
    salt2 = (tmp_path / SALT_FILENAME).read_text()

    assert salt1 == salt2


def test_init_creates_parent_directory(tmp_path: Path) -> None:
    nested = tmp_path / "nested" / "registream"
    init(nested)
    assert (nested / USAGE_FILENAME).exists()


# ─── log() ─────────────────────────────────────────────────────────────────────


def test_log_appends_row(tmp_path: Path) -> None:
    save_config(Config(usage_logging=True), tmp_path)
    log("test_command", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    path = tmp_path / USAGE_FILENAME
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter=";")
        rows = list(reader)

    assert len(rows) == 1
    row = rows[0]
    assert row["command_string"] == "test_command"
    assert row["module"] == "autolabel"
    assert row["module_version"] == "3.0.0"
    assert row["core_version"] == "3.0.0"
    assert row["platform"] == "python"
    assert row["user_id"]  # non-empty


def test_log_noop_when_usage_logging_disabled(tmp_path: Path) -> None:
    save_config(Config(usage_logging=False), tmp_path)
    log("test_command", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    # File should NOT be created when logging is disabled
    assert not (tmp_path / USAGE_FILENAME).exists()


def test_log_appends_multiple_rows(tmp_path: Path) -> None:
    save_config(Config(usage_logging=True), tmp_path)
    log("cmd1", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    log("cmd2", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    log("cmd3", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    with (tmp_path / USAGE_FILENAME).open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter=";")
        rows = list(reader)

    assert len(rows) == 3
    assert [r["command_string"] for r in rows] == ["cmd1", "cmd2", "cmd3"]


def test_log_auto_initializes_when_file_missing(tmp_path: Path) -> None:
    """log() should call init() implicitly if the file does not exist."""
    save_config(Config(usage_logging=True), tmp_path)
    assert not (tmp_path / USAGE_FILENAME).exists()

    log("first_command", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    assert (tmp_path / USAGE_FILENAME).exists()


# ─── compute_user_id() ─────────────────────────────────────────────────────────


def test_compute_user_id_returns_16_char_hex(tmp_path: Path) -> None:
    user_id = compute_user_id(tmp_path)
    assert isinstance(user_id, str)
    assert len(user_id) == 16
    assert all(c in "0123456789abcdef" for c in user_id)


def test_compute_user_id_deterministic_within_session(tmp_path: Path) -> None:
    """Same salt + same machine → same user_id."""
    init(tmp_path)
    id1 = compute_user_id(tmp_path)
    id2 = compute_user_id(tmp_path)
    assert id1 == id2


def test_compute_user_id_changes_with_salt(tmp_path: Path) -> None:
    """Different salt → different user_id."""
    init(tmp_path)
    id1 = compute_user_id(tmp_path)

    # Overwrite the salt
    (tmp_path / SALT_FILENAME).write_text("different_salt_value_xyz123")
    id2 = compute_user_id(tmp_path)

    assert id1 != id2


def test_salt_is_64_hex_chars(tmp_path: Path) -> None:
    init(tmp_path)
    salt = (tmp_path / SALT_FILENAME).read_text().strip()
    assert len(salt) == 64
    assert all(c in "0123456789abcdef" for c in salt)


# ─── stats() ───────────────────────────────────────────────────────────────────


def test_stats_returns_empty_when_no_file(tmp_path: Path) -> None:
    result = stats(tmp_path)
    assert isinstance(result, UsageStats)
    assert result.total_calls == 0
    assert result.unique_users == 0
    assert result.first_use is None
    assert result.last_use is None


def test_stats_counts_rows_for_current_user(tmp_path: Path) -> None:
    save_config(Config(usage_logging=True), tmp_path)
    log("cmd1", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)
    log("cmd2", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    result = stats(tmp_path)
    assert result.total_calls == 2
    assert result.user_id  # non-empty


def test_stats_first_and_last_use_set(tmp_path: Path) -> None:
    save_config(Config(usage_logging=True), tmp_path)
    log("cmd1", module="autolabel", module_version="3.0.0", core_version="3.0.0", directory=tmp_path)

    result = stats(tmp_path)
    assert result.first_use is not None
    assert result.last_use is not None


def test_stats_unique_users_counts_all(tmp_path: Path) -> None:
    """Manually inject rows from a different user_id and verify unique_users."""
    init(tmp_path)
    path = tmp_path / USAGE_FILENAME
    with path.open("a", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, delimiter=";")
        writer.writerow(
            ["2026-04-09T00:00:00Z", "AAAA", "python", "3.0.0", "cmd", "Linux", "3.13"]
        )
        writer.writerow(
            ["2026-04-09T00:00:01Z", "BBBB", "python", "3.0.0", "cmd", "Linux", "3.13"]
        )
        writer.writerow(
            ["2026-04-09T00:00:02Z", "AAAA", "python", "3.0.0", "cmd", "Linux", "3.13"]
        )

    result = stats(tmp_path, all_users=True)
    assert result.unique_users == 2
