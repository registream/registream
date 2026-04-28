"""First-run interactive wizard.

Three setup modes (Offline / Standard / Full). Idempotent; skips if
already completed. Set ``REGISTREAM_AUTO_APPROVE=yes`` for batch mode.
"""

from __future__ import annotations

import os
from pathlib import Path

from registream.config import Config, load, save
from registream.dirs import get_registream_dir

__all__ = [
    "WizardError",
    "run_wizard",
    "config_for_choice",
]


_AUTO_APPROVE_ENV = "REGISTREAM_AUTO_APPROVE"
_DEFAULT_CHOICE = "3"  # Full Mode (same default Stata uses for AUTO_APPROVE)


class WizardError(Exception):
    """Raised when the first-run wizard cannot complete (user aborted, EOF, etc.)."""


def run_wizard(
    directory: Path | str | None = None,
    *,
    force: bool = False,
) -> Config:
    """Run the first-run wizard and return the resulting :class:`Config`.

    Behaviour:

    1. If ``force=False`` (default) and the existing config has
       ``first_run_completed=True``, the wizard is skipped and the
       existing config is returned unchanged.
    2. If ``REGISTREAM_AUTO_APPROVE=yes`` (case-insensitive) is set in
       the environment, the wizard skips the interactive prompt and uses
       Full Mode defaults. Mirrors Stata's ``$REGISTREAM_AUTO_APPROVE``.
       The welcome banner is also suppressed in this mode.
    3. Otherwise, the wizard prints the three-option welcome banner and
       prompts the user via :func:`input` for a choice (``"1"``, ``"2"``,
       or ``"3"``). Invalid input is re-prompted until a valid choice is
       given (or the user types ``exit`` / ``quit`` / ``q`` to abort).

    The chosen preset is saved to ``<dir>/config_python.toml`` and
    returned. ``Config.first_run_completed`` is set to ``True`` so the
    wizard does not re-run on the next invocation.

    :raises WizardError: if the user aborts the wizard or stdin closes.
    """
    existing = load(directory)
    if not force and existing.first_run_completed:
        return existing

    if os.environ.get(_AUTO_APPROVE_ENV, "").lower() == "yes":
        choice = _DEFAULT_CHOICE
    else:
        _print_welcome(directory)
        choice = _prompt_choice()

    cfg = config_for_choice(choice)
    save(cfg, directory)
    return cfg


def config_for_choice(choice: str) -> Config:
    """Return the :class:`Config` preset for a given setup mode choice.

    :param choice: ``"1"`` (Offline), ``"2"`` (Standard), or ``"3"`` (Full).
    :raises ValueError: if ``choice`` is not one of the three valid values.

    The three presets mirror lines 130–172 of ``_rs_config.ado``:

    - **Offline**: usage on, telemetry off, no internet, no auto update check
    - **Standard**: usage on, telemetry off, internet on, auto update check on
    - **Full**: usage on, telemetry on, internet on, auto update check on

    All three set ``first_run_completed=True``.
    """
    if choice == "1":
        return Config(
            usage_logging=True,
            telemetry_enabled=False,
            internet_access=False,
            auto_update_check=False,
            first_run_completed=True,
        )
    if choice == "2":
        return Config(
            usage_logging=True,
            telemetry_enabled=False,
            internet_access=True,
            auto_update_check=True,
            first_run_completed=True,
        )
    if choice == "3":
        return Config(
            usage_logging=True,
            telemetry_enabled=True,
            internet_access=True,
            auto_update_check=True,
            first_run_completed=True,
        )
    raise ValueError(
        f"Invalid choice: {choice!r}. "
        f"Must be '1' (Offline), '2' (Standard), or '3' (Full)."
    )


# ─── Internal helpers ──────────────────────────────────────────────────────────


def _prompt_choice() -> str:
    """Prompt for choice 1/2/3 and re-prompt on invalid input.

    The user can also type ``exit``, ``quit``, or ``q`` to abort, which
    raises :class:`WizardError`. EOF on stdin (e.g. piped input runs out)
    also raises :class:`WizardError`.
    """
    while True:
        try:
            raw = input("Enter choice (1-3): ").strip().lower()
        except EOFError as exc:
            raise WizardError("First-run wizard aborted (EOF on stdin).") from exc

        if raw in ("1", "2", "3"):
            return raw
        if raw in ("exit", "quit", "q"):
            raise WizardError("First-run setup aborted by user.")
        print(f"Invalid choice {raw!r}. Please enter 1, 2, or 3 (or 'q' to abort).")


def _print_welcome(directory: Path | str | None) -> None:
    """Display the welcome banner with the three setup options."""
    dir_ = (
        get_registream_dir() if directory is None else Path(directory).expanduser()
    )
    rule = "─" * 60
    message = f"""
{rule}
RegiStream: First-Time Setup
{rule}

Welcome to RegiStream! Before we begin, please choose your setup mode.

Configuration directory: {dir_}

To use a custom directory, set REGISTREAM_DIR before importing.

Setup Options:

  1) Offline Mode
     • No internet connections
     • Manual metadata management
     • Local usage logging only (stays on your machine)

  2) Standard Mode
     • Automatic metadata downloads from registream.org
     • Automatic update checks (daily)
     • Local usage logging only (stays on your machine)
     • No online telemetry

  3) Full Mode (Help Improve RegiStream)
     • Everything in Standard Mode, plus:
     • Online telemetry: anonymized usage data to help improve
       RegiStream (commands run, version, OS; no dataset content)

Note: You can change these settings later via:
  >>> from registream.config import set_value
  >>> set_value('telemetry_enabled', False)

{rule}
"""
    print(message)
