"""Per-client configuration: TOML in ``config_python.toml``.

Typed :class:`Config` dataclass with the same preference fields as
Stata's ``config_stata.csv``. Each client has its own config file to
avoid write contention.
"""

from __future__ import annotations

import tomllib  # Python 3.11+ stdlib
from dataclasses import dataclass, fields, replace
from datetime import datetime
from pathlib import Path
from typing import Any

import tomli_w

from registream.dirs import get_registream_dir

__all__ = [
    "CONFIG_FILENAME",
    "Config",
    "config_path",
    "init",
    "load",
    "save",
    "get",
    "set_value",
]


CONFIG_FILENAME = "config_python.toml"


@dataclass
class Config:
    """Typed RegiStream Python client configuration.

    Defaults match Stata's "Full Mode" first-run preset (the AUTO_APPROVE
    default in ``_rs_config init``). All fields are optional and missing
    keys in the on-disk TOML fall back to these defaults.
    """

    usage_logging: bool = True
    telemetry_enabled: bool = True
    internet_access: bool = True
    auto_update_check: bool = True
    last_update_check: datetime | None = None
    update_available: bool = False
    latest_version: str = ""
    autolabel_update_available: bool = False
    autolabel_latest_version: str = ""
    datamirror_update_available: bool = False
    datamirror_latest_version: str = ""
    first_run_completed: bool = False


def config_path(directory: Path | str | None = None) -> Path:
    """Return the path to the Python config file inside ``directory``.

    Defaults to ``<registream_user_dir>/config_python.toml`` where the
    user dir is resolved by :func:`registream.dirs.get_registream_dir`.
    """
    return _resolve_dir(directory) / CONFIG_FILENAME


def init(directory: Path | str | None = None) -> Config:
    """Ensure the config file exists; create with defaults if it does not.

    Mirrors ``_rs_config init`` from the Stata side. Idempotent; if the
    file already exists, the current config is returned unchanged.

    On a read-only filesystem this returns the in-memory defaults without
    raising; same graceful fallback as Stata's init logic, which sets
    ``r(writable) = 0`` instead of failing.

    The Python ``init`` does NOT run the interactive first-run wizard;
    it always uses Full Mode defaults (matching Stata's ``$REGISTREAM_AUTO_APPROVE``
    behaviour). The interactive wizard lives in :mod:`registream.first_run`
    and is invoked separately.
    """
    path = config_path(directory)

    if path.exists():
        return load(directory)

    cfg = Config()
    try:
        save(cfg, directory)
    except OSError:
        # Read-only system or permission error: return in-memory defaults
        # without crashing. Stata does the same with `r(writable) == 0`.
        pass

    return cfg


def load(directory: Path | str | None = None) -> Config:
    """Load the config from disk, returning a typed :class:`Config`.

    If the file does not exist, returns ``Config()`` (defaults) without
    writing anything. Unknown keys in the TOML are silently ignored for
    forward compatibility: older code reading a newer config with extra
    fields will not crash.
    """
    path = config_path(directory)

    if not path.exists():
        return Config()

    with path.open("rb") as fh:
        data = tomllib.load(fh)

    known = {f.name for f in fields(Config)}
    filtered = {k: v for k, v in data.items() if k in known}

    return Config(**filtered)


def save(cfg: Config, directory: Path | str | None = None) -> None:
    """Write the config to disk in TOML format.

    Creates the parent directory if it does not exist. The TOML output omits
    keys whose value is ``None`` (TOML has no null type); those keys come
    back as defaults on the next :func:`load`.
    """
    path = config_path(directory)
    path.parent.mkdir(parents=True, exist_ok=True)

    data: dict[str, Any] = {}
    for f in fields(cfg):
        value = getattr(cfg, f.name)
        if value is None:
            continue  # TOML has no null
        data[f.name] = value

    with path.open("wb") as fh:
        tomli_w.dump(data, fh)


def get(key: str, directory: Path | str | None = None) -> Any:
    """Get a single config value by key (Stata ``_rs_config get`` equivalent).

    Returns the field's default if the key is missing from the file. Raises
    :class:`KeyError` if the key is not a known :class:`Config` field.
    """
    if key not in {f.name for f in fields(Config)}:
        raise KeyError(f"Unknown config key: {key!r}")

    cfg = load(directory)
    return getattr(cfg, key)


def set_value(key: str, value: Any, directory: Path | str | None = None) -> None:
    """Set a single config value by key (Stata ``_rs_config set`` equivalent).

    Named ``set_value`` rather than ``set`` to avoid shadowing Python's
    built-in ``set`` type at the module level. Loads the current config,
    updates the field, and writes back. Raises :class:`KeyError` if the key
    is unknown.
    """
    if key not in {f.name for f in fields(Config)}:
        raise KeyError(f"Unknown config key: {key!r}")

    cfg = load(directory)
    cfg = replace(cfg, **{key: value})
    try:
        save(cfg, directory)
    except OSError as exc:
        path = config_path(directory)
        raise OSError(
            f"Cannot write config: {path} is read-only or inaccessible.\n"
            f"Point RegiStream at a writable directory by setting the "
            f"REGISTREAM_DIR environment variable."
        ) from exc


def _resolve_dir(directory: Path | str | None) -> Path:
    """Resolve ``directory`` to a :class:`Path`, defaulting to the user dir."""
    if directory is None:
        return get_registream_dir()
    return Path(directory).expanduser()
