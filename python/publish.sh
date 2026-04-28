#!/usr/bin/env bash
# publish_python.sh: interactive publish of a RegiStream Python distribution
#
# Usage:
#   ./publish_python.sh <package> [--testpypi] [--dry-run]
#
# Packages:
#   registream-core         the shared core distribution
#   registream-autolabel    the autolabel module
#   registream              the metapackage (depends on core + autolabel)
#
# Flags:
#   --testpypi              publish to test.pypi.org instead of pypi.org (default: pypi.org)
#   --dry-run               build only; do not prompt for token or publish
#   -h, --help              show this message
#
# Behavior:
#   - Builds the wheel + sdist with `uv build` inside the package directory
#   - Confirms with the user before publishing (interactive yes/no)
#   - Prompts for the PyPI API token interactively (silent input via `read -rsp`)
#   - Passes the token to `uv publish` via UV_PUBLISH_TOKEN env var
#   - Token is NEVER written to disk, env file, shell history, or any cache;
#     it lives in process memory only and dies when this script exits
#
# Layout assumption:
#   This script lives at registream/scripts/publish_python.sh and the RegiStream
#   module repos are cloned as siblings under one parent directory (the
#   registream-org/ convention). Path resolution walks up two levels.

set -euo pipefail

# ─── Help ────────────────────────────────────────────────────────────────────
print_help() {
    sed -n '2,29p' "$0" | sed 's/^# \?//'
}

# ─── Argument parsing ────────────────────────────────────────────────────────
package="${1:-}"
target="pypi"
dry_run=0

if [ -z "$package" ] || [ "$package" = "-h" ] || [ "$package" = "--help" ]; then
    print_help
    [ -z "$package" ] && exit 2 || exit 0
fi
shift

for arg in "$@"; do
    case "$arg" in
        --testpypi) target="testpypi" ;;
        --dry-run)  dry_run=1 ;;
        -h|--help)  print_help; exit 0 ;;
        *)
            echo "ERROR: unknown argument '$arg'" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

# ─── Sanity: uv must be on PATH ──────────────────────────────────────────────
if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv not found on PATH." >&2
    echo "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
    exit 1
fi

# ─── Resolve package directory (sibling-clone layout) ────────────────────────
script_dir="$(cd "$(dirname "$0")" && pwd)"
repos_root="$(cd "$script_dir/../.." && pwd)"

case "$package" in
    registream-core)
        pkg_dir="$repos_root/registream/python/registream-core"
        ;;
    registream-autolabel)
        pkg_dir="$repos_root/autolabel/python/registream-autolabel"
        ;;
    registream)
        pkg_dir="$repos_root/registream/python/registream-meta"
        ;;
    *)
        echo "ERROR: unknown package '$package'" >&2
        echo "Valid packages: registream-core, registream-autolabel, registream" >&2
        exit 2
        ;;
esac

if [ ! -f "$pkg_dir/pyproject.toml" ]; then
    echo "ERROR: $pkg_dir/pyproject.toml not found." >&2
    echo "Expected sibling-clone layout under $repos_root" >&2
    echo "All RegiStream module repos must be cloned as siblings under one parent dir." >&2
    exit 1
fi

# ─── Resolve publish target ──────────────────────────────────────────────────
case "$target" in
    pypi)
        publish_url="https://upload.pypi.org/legacy/"
        view_url_base="https://pypi.org/project"
        target_label="REAL PyPI (https://pypi.org)"
        ;;
    testpypi)
        publish_url="https://test.pypi.org/legacy/"
        view_url_base="https://test.pypi.org/project"
        target_label="TestPyPI (https://test.pypi.org)"
        ;;
esac

echo "==> Package : $package"
echo "==> Source  : $pkg_dir"
echo "==> Target  : $target_label"
echo

# ─── Build ───────────────────────────────────────────────────────────────────
echo "==> Building (uv build)"
cd "$pkg_dir"
rm -rf dist/
uv build
echo

echo "==> Built artifacts:"
ls -lh dist/
echo

if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] Would publish dist/* to $publish_url"
    echo "[dry-run] No token prompted, no upload attempted."
    exit 0
fi

# ─── Confirm with user (interactive yes/no) ──────────────────────────────────
echo "==> About to publish $package to $target_label"
read -rp "    Proceed? [type 'yes' to continue] " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# ─── Prompt for token (silent input, never persisted) ────────────────────────
echo
read -rsp "==> PyPI API token (paste; will not echo): " token
echo
if [ -z "$token" ]; then
    echo "ERROR: empty token, aborting." >&2
    exit 1
fi

# ─── Publish ─────────────────────────────────────────────────────────────────
echo "==> Publishing $package to $target_label..."
UV_PUBLISH_TOKEN="$token" UV_PUBLISH_URL="$publish_url" uv publish dist/*

# Token goes out of scope when the script exits; no persistence anywhere.
unset token

echo
echo "==> Done."
echo "    View at: $view_url_base/$package/"
