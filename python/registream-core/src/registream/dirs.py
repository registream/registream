"""Cross-platform resolution of the RegiStream user-data directory.

This module is the only place that handles OS differences for the
``~/.registream/`` directory. All callers use :func:`get_registream_dir`
and trust the result.

Mirrors the Stata ``_rs_utils get_dir`` subcommand line for line, including
the Windows-specific path under ``AppData/Local/registream`` (NOT
``~/.registream`` on Windows).
"""

from __future__ import annotations

import os
import platform
from pathlib import Path

__all__ = ["get_registream_dir"]


def get_registream_dir() -> Path:
    """Return the user-level RegiStream directory.

    Resolution order:

    1. The ``REGISTREAM_DIR`` environment variable, if set (mirrors Stata's
       ``$registream_dir`` global). The path is expanded with ``~``.
    2. Per-OS default:

       - macOS / Linux: ``~/.registream``
       - Windows: ``~/AppData/Local/registream``

    The directory is **not** created; that is the caller's responsibility,
    typically the config or metadata layer when it first writes a file.
    """
    override = os.environ.get("REGISTREAM_DIR")
    if override:
        return Path(override).expanduser()

    home = Path.home()
    system = platform.system()

    if system in ("Darwin", "Linux"):
        return home / ".registream"
    if system == "Windows":
        return home / "AppData" / "Local" / "registream"

    raise RuntimeError(
        f"Cannot determine RegiStream directory for unsupported OS: {system!r}"
    )
