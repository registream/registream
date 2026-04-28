"""Unit tests for registream.utils."""

from __future__ import annotations

import pytest

from registream.utils import PromptDeclined, confirm, escape_ascii, get_api_host


# ─── escape_ascii ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("", ""),
        ("plain", "plain"),
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
    ],
)
def test_escape_ascii_single_chars(raw: str, expected: str) -> None:
    assert escape_ascii(raw) == expected


def test_escape_ascii_known_string() -> None:
    """The cache-key generation contract: 'scb_lisa' → 'scbq95lisa'.

    This must match Stata's `_utils_escape_ascii "scb_lisa"` output exactly.
    Divergence here breaks shared metadata cache compatibility.
    """
    assert escape_ascii("scb_lisa") == "scbq95lisa"


def test_escape_ascii_multiple_specials() -> None:
    assert escape_ascii("a.b/c-d") == "aq46bq47cq45d"


def test_escape_ascii_no_specials_unchanged() -> None:
    assert escape_ascii("abc123XYZ") == "abc123XYZ"


def test_escape_ascii_idempotent_on_safe_input() -> None:
    safe = "abc123"
    assert escape_ascii(escape_ascii(safe)) == safe


# ─── get_api_host ──────────────────────────────────────────────────────────────


def test_get_api_host_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_API_HOST", raising=False)
    assert get_api_host() == "https://registream.org"


def test_get_api_host_env_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REGISTREAM_API_HOST", "https://dev.example.org")
    assert get_api_host() == "https://dev.example.org"


# ─── confirm ───────────────────────────────────────────────────────────────────


def test_confirm_auto_approve_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "yes")
    assert confirm("anything?") is True


def test_confirm_auto_approve_case_insensitive(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REGISTREAM_AUTO_APPROVE", "YES")
    assert confirm("anything?") is True


def test_confirm_yes_reply(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", lambda _prompt="": "y")
    assert confirm("download?") is True


def test_confirm_no_reply(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", lambda _prompt="": "n")
    assert confirm("download?") is False


def test_confirm_empty_uses_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)
    monkeypatch.setattr("builtins.input", lambda _prompt="": "")
    assert confirm("download?", default=True) is True
    assert confirm("download?", default=False) is False


def test_confirm_eof_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REGISTREAM_AUTO_APPROVE", raising=False)

    def _raise_eof(_prompt: str = "") -> str:
        raise EOFError

    monkeypatch.setattr("builtins.input", _raise_eof)
    with pytest.raises(PromptDeclined):
        confirm("download?")
