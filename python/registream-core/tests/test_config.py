"""Unit tests for registream.config."""

from __future__ import annotations

import tomllib
from datetime import datetime, timezone
from pathlib import Path

import pytest

from registream.config import (
    CONFIG_FILENAME,
    Config,
    config_path,
    get,
    init,
    load,
    save,
    set_value,
)


# ─── config_path ───────────────────────────────────────────────────────────────


def test_config_path_default_uses_registream_dir(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("REGISTREAM_DIR", str(tmp_path))
    assert config_path() == tmp_path / CONFIG_FILENAME


def test_config_path_explicit_directory(tmp_path: Path) -> None:
    assert config_path(tmp_path) == tmp_path / CONFIG_FILENAME


def test_config_path_filename_is_config_python_toml(tmp_path: Path) -> None:
    """Per-client convention: Python uses config_python.toml, not config_stata.csv."""
    assert config_path(tmp_path).name == "config_python.toml"


# ─── load() defaults ───────────────────────────────────────────────────────────


def test_load_returns_defaults_when_no_file(tmp_path: Path) -> None:
    cfg = load(tmp_path)

    assert isinstance(cfg, Config)
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True
    assert cfg.last_update_check is None
    assert cfg.update_available is False
    assert cfg.latest_version == ""
    assert cfg.first_run_completed is False


def test_load_does_not_create_file(tmp_path: Path) -> None:
    """load() must be a pure read; no side effects on the filesystem."""
    load(tmp_path)
    assert not (tmp_path / CONFIG_FILENAME).exists()


# ─── save() ────────────────────────────────────────────────────────────────────


def test_save_creates_file(tmp_path: Path) -> None:
    save(Config(), tmp_path)
    assert (tmp_path / CONFIG_FILENAME).exists()


def test_save_creates_parent_directory(tmp_path: Path) -> None:
    nested = tmp_path / "nested" / "registream"
    save(Config(), nested)
    assert (nested / CONFIG_FILENAME).exists()


def test_save_writes_valid_toml(tmp_path: Path) -> None:
    save(Config(), tmp_path)
    raw = (tmp_path / CONFIG_FILENAME).read_bytes()

    # Must parse as TOML without raising
    parsed = tomllib.loads(raw.decode("utf-8"))
    assert "usage_logging" in parsed


# ─── round-trip ────────────────────────────────────────────────────────────────


def test_round_trip_preserves_all_fields(tmp_path: Path) -> None:
    original = Config(
        usage_logging=False,
        telemetry_enabled=False,
        internet_access=False,
        auto_update_check=False,
        last_update_check=datetime(2026, 4, 9, 10, 23, 0, tzinfo=timezone.utc),
        update_available=True,
        latest_version="3.1.0",
        first_run_completed=True,
    )
    save(original, tmp_path)
    loaded = load(tmp_path)

    assert loaded == original


def test_round_trip_preserves_datetime_type(tmp_path: Path) -> None:
    cfg = Config(last_update_check=datetime(2026, 4, 9, 10, 23, 0, tzinfo=timezone.utc))
    save(cfg, tmp_path)
    loaded = load(tmp_path)

    assert isinstance(loaded.last_update_check, datetime)


def test_save_omits_none_fields(tmp_path: Path) -> None:
    """TOML has no null type; None values must be omitted, not crash."""
    cfg = Config(last_update_check=None)
    save(cfg, tmp_path)

    raw = (tmp_path / CONFIG_FILENAME).read_text()
    assert "last_update_check" not in raw

    loaded = load(tmp_path)
    assert loaded.last_update_check is None


def test_load_ignores_unknown_keys(tmp_path: Path) -> None:
    """Forward compatibility: extra TOML keys must be silently ignored."""
    raw = b'usage_logging = false\nsome_future_field = "ignored"\n'
    (tmp_path / CONFIG_FILENAME).write_bytes(raw)

    cfg = load(tmp_path)
    assert cfg.usage_logging is False


# ─── init() ────────────────────────────────────────────────────────────────────


def test_init_creates_file_when_missing(tmp_path: Path) -> None:
    cfg = init(tmp_path)
    assert (tmp_path / CONFIG_FILENAME).exists()
    assert cfg.usage_logging is True  # Full mode default


def test_init_returns_config_instance(tmp_path: Path) -> None:
    assert isinstance(init(tmp_path), Config)


def test_init_idempotent_when_file_exists(tmp_path: Path) -> None:
    """init() must not overwrite an existing config."""
    custom = Config(usage_logging=False, internet_access=False)
    save(custom, tmp_path)

    cfg = init(tmp_path)
    assert cfg.usage_logging is False
    assert cfg.internet_access is False


def test_init_full_mode_defaults(tmp_path: Path) -> None:
    """Without the interactive wizard, init() must produce Full Mode defaults."""
    cfg = init(tmp_path)
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True


def test_per_module_cache_fields_in_defaults() -> None:
    """Per-module cache fields exist in Config defaults and round-trip (Gap 2)."""
    cfg = Config()
    assert cfg.autolabel_update_available is False
    assert cfg.autolabel_latest_version == ""
    assert cfg.datamirror_update_available is False
    assert cfg.datamirror_latest_version == ""


# ─── get() / set_value() helpers (Stata-style mirror API) ──────────────────────


def test_get_helper_reads_value(tmp_path: Path) -> None:
    save(Config(internet_access=False), tmp_path)
    assert get("internet_access", tmp_path) is False


def test_get_helper_returns_default_when_key_absent_from_file(tmp_path: Path) -> None:
    """File exists but key missing → fall back to dataclass default."""
    raw = b"usage_logging = false\n"
    (tmp_path / CONFIG_FILENAME).write_bytes(raw)

    # internet_access not in file → falls back to default (True)
    assert get("internet_access", tmp_path) is True
    assert get("usage_logging", tmp_path) is False


def test_get_helper_raises_on_unknown_key(tmp_path: Path) -> None:
    save(Config(), tmp_path)
    with pytest.raises(KeyError):
        get("not_a_real_key", tmp_path)


def test_set_value_helper_writes(tmp_path: Path) -> None:
    save(Config(), tmp_path)
    set_value("usage_logging", False, tmp_path)
    assert load(tmp_path).usage_logging is False


def test_set_value_helper_creates_file_implicitly(tmp_path: Path) -> None:
    """Calling set_value() without prior init() should still work."""
    set_value("usage_logging", False, tmp_path)
    assert load(tmp_path).usage_logging is False


def test_set_value_helper_raises_on_unknown_key(tmp_path: Path) -> None:
    with pytest.raises(KeyError):
        set_value("not_a_real_key", True, tmp_path)


# ─── per-client file split ─────────────────────────────────────────────────────


def test_python_uses_toml_not_csv(tmp_path: Path) -> None:
    """Python's config file is config_python.toml, NOT config_stata.csv.

    This is the per-client split from `08_PYTHON_ECOSYSTEM.md`'s "Why
    per-client configs and not a shared preferences file"; both clients
    own their own config file, no write contention, no schema coupling.
    """
    save(Config(), tmp_path)
    assert (tmp_path / "config_python.toml").exists()
    assert not (tmp_path / "config_stata.csv").exists()
