"""Unit tests for registream.dirs."""

from __future__ import annotations

import os
import platform
from pathlib import Path

import pytest

from registream.dirs import get_registream_dir


def test_default_path_on_current_os(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_DIR", raising=False)

    result = get_registream_dir()
    home = Path.home()
    system = platform.system()

    if system in ("Darwin", "Linux"):
        assert result == home / ".registream"
    elif system == "Windows":
        assert result == home / "AppData" / "Local" / "registream"
    else:
        pytest.skip(f"unsupported OS for default-path check: {system}")


def test_environment_override(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("REGISTREAM_DIR", str(tmp_path))
    assert get_registream_dir() == tmp_path


def test_environment_override_expands_tilde(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REGISTREAM_DIR", "~/custom-registream")
    assert get_registream_dir() == Path.home() / "custom-registream"


def test_returns_path_not_string(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_DIR", raising=False)
    assert isinstance(get_registream_dir(), Path)


def test_does_not_create_directory(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """get_registream_dir() must not have side effects on the filesystem."""
    target = tmp_path / "new-registream"
    assert not target.exists()
    monkeypatch.setenv("REGISTREAM_DIR", str(target))

    _ = get_registream_dir()
    assert not target.exists(), "get_registream_dir() must not mkdir"
