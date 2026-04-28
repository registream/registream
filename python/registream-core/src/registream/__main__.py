"""Command-line entry point for ``python -m registream``.

Mirrors the Stata ``registream`` subcommand surface. Thin dispatcher:
each subcommand calls an existing function and prints its result.

Subcommands
-----------

- ``version``: print ``registream-core <version>``
- ``info``   : print ``registream.info.info()`` output (config + cache)
- ``cite``   : print the full citation block (mirrors Stata ``registream cite``)
"""

from __future__ import annotations

import argparse
import sys
from importlib.metadata import PackageNotFoundError, version


def _cmd_version() -> int:
    try:
        v = version("registream-core")
    except PackageNotFoundError:
        print("registream-core (not installed)", file=sys.stderr)
        return 1
    print(f"registream-core {v}")
    return 0


def _cmd_info() -> int:
    from registream.info import info

    sys.stdout.write(info())
    return 0


def _cmd_cite() -> int:
    from registream.citation import cite

    print(cite())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m registream",
        description="RegiStream core: command-line access to version, info, and citation.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("version", help="print the installed registream-core version")
    sub.add_parser("info", help="print the current RegiStream configuration")
    sub.add_parser("cite", help="print the project citation block (matches Stata 'registream cite')")

    args = parser.parse_args(argv)
    if args.command == "version":
        return _cmd_version()
    if args.command == "info":
        return _cmd_info()
    if args.command == "cite":
        return _cmd_cite()
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
