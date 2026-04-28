"""Shared utility helpers: API host resolution, string escaping, prompts."""

from __future__ import annotations

import os

__all__ = ["PromptDeclined", "confirm", "escape_ascii", "get_api_host"]


_AUTO_APPROVE_ENV = "REGISTREAM_AUTO_APPROVE"


class PromptDeclined(RuntimeError):
    """Raised when an interactive confirmation cannot be answered."""


def confirm(message: str, *, default: bool = False) -> bool:
    """Ask a yes/no question, honoring ``REGISTREAM_AUTO_APPROVE``.

    Mirrors Stata's ``_rs_utils prompt``: ``REGISTREAM_AUTO_APPROVE=yes``
    (case-insensitive) short-circuits to ``True`` so batch tests and CI run
    non-interactively. Otherwise calls :func:`input`, accepting ``y``/``yes``
    or ``n``/``no``; empty reply falls back to ``default``.

    :raises PromptDeclined: stdin is closed with no auto-approve set; the
        caller must set the env var or pass an explicit opt-in (``force=True``).
    """
    if os.environ.get(_AUTO_APPROVE_ENV, "").lower() == "yes":
        return True

    hint = "[Y/n]" if default else "[y/N]"
    try:
        raw = input(f"{message} {hint}: ").strip().lower()
    except EOFError as exc:
        raise PromptDeclined(
            f"Cannot prompt in non-interactive session. "
            f"Set {_AUTO_APPROVE_ENV}=yes or pass an explicit opt-in."
        ) from exc

    if raw == "":
        return default
    return raw in ("y", "yes")


# Q-code escape table: must match `_utils_escape_ascii` in
# stata/src/_rs_utils.ado exactly. Both clients hash arbitrary strings
# (domain names, register names) into safe filenames using this mapping;
# any divergence breaks shared metadata cache compatibility.
_ASCII_ESCAPES: tuple[tuple[str, str], ...] = (
    (".", "q46"),
    ("*", "q42"),
    ("/", "q47"),
    ("&", "q38"),
    ("-", "q45"),
    ("_", "q95"),
    ("[", "q91"),
    ("]", "q93"),
    ("{", "q123"),
    ("}", "q125"),
    (" ", "q32"),
)


def escape_ascii(s: str) -> str:
    """Escape special characters in ``s`` using the q-code mapping.

    Replaces a fixed set of punctuation/whitespace characters with
    ``q<ASCII-decimal>`` so the result is safe to use in filenames. Round-trips
    with the Stata ``_rs_utils escape_ascii`` helper; both clients must
    produce the same output for the same input or the shared metadata cache
    breaks.
    """
    for raw, escaped in _ASCII_ESCAPES:
        s = s.replace(raw, escaped)
    return s


def get_api_host() -> str:
    """Return the RegiStream API host URL.

    Defaults to the production host ``https://registream.org``. Override with
    the ``REGISTREAM_API_HOST`` environment variable for local development or
    testing; this mirrors the Stata ``_rs_dev_utils get_host`` hook used to
    point at a development server.
    """
    return os.environ.get("REGISTREAM_API_HOST", "https://registream.org")
