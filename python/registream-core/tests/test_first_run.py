"""Unit tests for registream.first_run."""

from __future__ import annotations

from pathlib import Path
from typing import Iterator

import pytest

from registream.config import Config, load, save
from registream.first_run import (
    WizardError,
    config_for_choice,
    run_wizard,
)


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _make_input_mock(*responses: str):
    """Build an ``input()`` mock that returns successive responses."""
    iterator: Iterator[str] = iter(responses)
    return lambda _prompt="": next(iterator)


# ─── config_for_choice ────────────────────────────────────────────────────────


def test_config_for_choice_offline_mode() -> None:
    """Offline: usage on, everything network-related off."""
    cfg = config_for_choice("1")
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is False
    assert cfg.internet_access is False
    assert cfg.auto_update_check is False
    assert cfg.first_run_completed is True


def test_config_for_choice_standard_mode() -> None:
    """Standard: internet on but no telemetry."""
    cfg = config_for_choice("2")
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is False
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True
    assert cfg.first_run_completed is True


def test_config_for_choice_full_mode() -> None:
    """Full: everything on, including telemetry."""
    cfg = config_for_choice("3")
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True
    assert cfg.first_run_completed is True


def test_config_for_choice_all_three_set_first_run_completed() -> None:
    """Every preset must mark first_run_completed=True."""
    for choice in ("1", "2", "3"):
        assert config_for_choice(choice).first_run_completed is True


def test_config_for_choice_invalid_raises() -> None:
    with pytest.raises(ValueError, match="Invalid choice"):
        config_for_choice("invalid")


def test_config_for_choice_zero_raises() -> None:
    with pytest.raises(ValueError, match="Invalid choice"):
        config_for_choice("0")


def test_config_for_choice_four_raises() -> None:
    with pytest.raises(ValueError, match="Invalid choice"):
        config_for_choice("4")


# ─── run_wizard with AUTO_APPROVE ─────────────────────────────────────────────


def test_run_wizard_auto_approve_uses_full_mode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")
    cfg = run_wizard(tmp_path)

    # Full Mode preset
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True
    assert cfg.auto_update_check is True
    assert cfg.first_run_completed is True


def test_run_wizard_auto_approve_does_not_prompt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """With AUTO_APPROVE set, ``input()`` must NOT be called."""
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")

    def _fail(*args, **kwargs):
        raise AssertionError("input() must not be called when AUTO_APPROVE=yes")

    monkeypatch.setattr("builtins.input", _fail)
    run_wizard(tmp_path)  # should not raise


def test_run_wizard_auto_approve_case_insensitive(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "YES")
    cfg = run_wizard(tmp_path)
    assert cfg.first_run_completed is True


def test_run_wizard_auto_approve_does_not_print_banner(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """When AUTO_APPROVE is set, the welcome banner must NOT be printed.

    Otherwise batch / test runs would emit noise on stdout.
    """
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")
    run_wizard(tmp_path)

    captured = capsys.readouterr()
    assert "First-Time Setup" not in captured.out


# ─── run_wizard with mocked input ─────────────────────────────────────────────


def test_run_wizard_choice_1_offline(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("1"))

    cfg = run_wizard(tmp_path)
    assert cfg.internet_access is False
    assert cfg.telemetry_enabled is False
    assert cfg.first_run_completed is True


def test_run_wizard_choice_2_standard(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("2"))

    cfg = run_wizard(tmp_path)
    assert cfg.internet_access is True
    assert cfg.telemetry_enabled is False
    assert cfg.auto_update_check is True


def test_run_wizard_choice_3_full(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("3"))

    cfg = run_wizard(tmp_path)
    assert cfg.telemetry_enabled is True
    assert cfg.internet_access is True


# ─── run_wizard idempotency ───────────────────────────────────────────────────


def test_run_wizard_skips_when_first_run_completed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """If ``first_run_completed`` is already True, the wizard returns the
    existing config without re-prompting."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    save(Config(first_run_completed=True, usage_logging=False), tmp_path)

    def _fail(*args, **kwargs):
        raise AssertionError("input() must not be called when first_run_completed")

    monkeypatch.setattr("builtins.input", _fail)
    cfg = run_wizard(tmp_path)
    assert cfg.usage_logging is False  # existing value preserved
    assert cfg.first_run_completed is True


def test_run_wizard_force_re_runs_even_if_completed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``force=True`` re-runs the wizard even if it has been completed before."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    save(Config(first_run_completed=True, usage_logging=False), tmp_path)
    monkeypatch.setattr("builtins.input", _make_input_mock("3"))

    cfg = run_wizard(tmp_path, force=True)
    # Force re-ran, picked Full Mode → usage_logging back to True
    assert cfg.usage_logging is True
    assert cfg.telemetry_enabled is True


# ─── run_wizard saves to disk ────────────────────────────────────────────────


def test_run_wizard_saves_config_to_disk(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")
    run_wizard(tmp_path)

    loaded = load(tmp_path)
    assert loaded.first_run_completed is True
    assert loaded.telemetry_enabled is True


def test_run_wizard_persists_choice_across_load(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A wizard run with choice 1 (Offline) must round-trip through the file."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("1"))

    run_wizard(tmp_path)
    reloaded = load(tmp_path)
    assert reloaded.internet_access is False
    assert reloaded.first_run_completed is True


# ─── run_wizard invalid input handling ───────────────────────────────────────


def test_run_wizard_retries_on_invalid_input(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Invalid input should trigger a re-prompt, not abort."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("abc", "5", "2"))

    cfg = run_wizard(tmp_path)
    assert cfg.internet_access is True  # Standard mode (third response)
    assert cfg.auto_update_check is True

    captured = capsys.readouterr()
    # Should have printed at least one "Invalid choice" message
    assert "Invalid choice" in captured.out


def test_run_wizard_quit_aborts_with_wizard_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("q"))

    with pytest.raises(WizardError, match="aborted by user"):
        run_wizard(tmp_path)


def test_run_wizard_exit_aborts_with_wizard_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("exit"))

    with pytest.raises(WizardError, match="aborted by user"):
        run_wizard(tmp_path)


def test_run_wizard_eof_raises_wizard_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """If stdin closes (EOF), the wizard raises WizardError, not crashes."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)

    def _eof(_prompt=""):
        raise EOFError()

    monkeypatch.setattr("builtins.input", _eof)
    with pytest.raises(WizardError, match="EOF"):
        run_wizard(tmp_path)


# ─── welcome banner content ───────────────────────────────────────────────────


def test_run_wizard_prints_welcome_banner(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The welcome banner mentions all three modes by name."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("3"))

    run_wizard(tmp_path)

    captured = capsys.readouterr()
    assert "RegiStream" in captured.out
    assert "First-Time Setup" in captured.out
    assert "Offline Mode" in captured.out
    assert "Standard Mode" in captured.out
    assert "Full Mode" in captured.out


def test_run_wizard_banner_shows_directory(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The banner shows the user where the config will live."""
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", _make_input_mock("3"))

    run_wizard(tmp_path)

    captured = capsys.readouterr()
    assert str(tmp_path) in captured.out
