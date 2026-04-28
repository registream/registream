"""Display the current RegiStream configuration. Mirrors Stata ``registream info``.

Returns a multi-line string the caller prints. The Stata equivalent
``_registream_info`` writes to stdout directly; the Python version separates
content from display so the result can be tested, captured, or formatted
for a Jupyter notebook.
"""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

from registream import _citation_data as _cd
from registream.config import config_path, load
from registream.dirs import get_registream_dir

__all__ = ["info"]


def info(directory: Path | str | None = None) -> str:
    """Return a multi-line string with the current RegiStream configuration.

    Mirrors Stata ``registream info``. Includes:

    - The user-data directory and the config file path
    - The installed registream-core version
    - The four boolean settings (usage_logging, telemetry_enabled,
      internet_access, auto_update_check)
    - The short citation block
    """
    dir_ = get_registream_dir() if directory is None else Path(directory).expanduser()
    cfg = load(dir_)

    try:
        ver = version("registream-core")
    except PackageNotFoundError:
        ver = "unknown"

    lines = [
        "",
        "─" * 60,
        "RegiStream Configuration",
        "─" * 60,
        f"Directory:        {dir_}",
        f"Config file:      {config_path(dir_)}",
        "",
        "Package:",
        f"  version:         {ver}",
        "",
        "Settings:",
        f"  usage_logging:       {str(cfg.usage_logging).lower()}",
        f"  telemetry_enabled:   {str(cfg.telemetry_enabled).lower()}",
        f"  internet_access:     {str(cfg.internet_access).lower()}",
        f"  auto_update_check:   {str(cfg.auto_update_check).lower()}",
        "─" * 60,
        "",
        "Citation:",
        "  " + _cd.APA,
        "",
    ]
    return "\n".join(lines)
