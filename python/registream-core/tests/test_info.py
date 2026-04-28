"""Unit tests for registream.info."""

from __future__ import annotations

from importlib.metadata import version
from pathlib import Path

from registream.info import info


def test_info_returns_string(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert isinstance(text, str)
    assert text


def test_info_contains_directory(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert str(tmp_path) in text


def test_info_contains_version(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert version("registream-core") in text


def test_info_contains_settings_keys(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert "usage_logging" in text
    assert "telemetry_enabled" in text
    assert "internet_access" in text
    assert "auto_update_check" in text


def test_info_contains_citation(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert "Clark, J. & Wen, J." in text
    assert "https://registream.org" in text


def test_info_contains_configuration_label(tmp_path: Path) -> None:
    text = info(tmp_path)
    assert "RegiStream Configuration" in text


def test_info_reflects_modified_settings(tmp_path: Path) -> None:
    """When settings differ from defaults, info should show the new values."""
    from registream.config import Config, save

    save(Config(usage_logging=False, telemetry_enabled=False), tmp_path)
    text = info(tmp_path)
    # Both should appear as 'false' (lowercased)
    assert "usage_logging:       false" in text
    assert "telemetry_enabled:   false" in text
