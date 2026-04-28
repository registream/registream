#!/usr/bin/env bash
# =============================================================================
# Sync registream-website artifacts (Stata + R) to submira-prod.
# =============================================================================
#
# Defaults to dry-run. Pass --apply to actually transfer.
#
# What this script transfers (gitignored, must rsync):
#   - data/registream/stata/   per-package folders + zips
#   - data/registream/r/       CRAN-format R package repository
#
# What this script does NOT transfer (handled by `git pull` on the server):
#   - app/, scripts/, tests/   code
#   - data/registream/{package_manifest.yaml, changelog.json, datasets.yaml}
#
# Full release = run this script AND `ssh submira-prod 'cd /srv/registream-website && git pull'`.
#
# Usage:
#   ./sync_artifacts.sh           # dry-run (default)
#   ./sync_artifacts.sh --apply   # real transfer
#   ./sync_artifacts.sh --build   # build Stata artifacts first, then dry-run
#   ./sync_artifacts.sh --build --apply
# =============================================================================

set -euo pipefail

# Resolve paths: this script lives at registream/sync_artifacts.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTREAM="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEBSITE="$REPO_ROOT/registream-website"

REMOTE="submira-prod"
REMOTE_PATH="/srv/registream-website"

# Parse flags
DO_BUILD=0
DO_APPLY=0
for arg in "$@"; do
    case "$arg" in
        --build) DO_BUILD=1 ;;
        --apply) DO_APPLY=1 ;;
        -h|--help)
            sed -n '2,/^# ===/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            echo "Usage: $0 [--build] [--apply]" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$WEBSITE/data/registream" ]]; then
    echo "ERROR: $WEBSITE/data/registream not found" >&2
    echo "Expected sibling repo at $WEBSITE" >&2
    exit 1
fi

# Optional rebuild step
if [[ "$DO_BUILD" -eq 1 ]]; then
    echo "=== Building Stata artifacts from source ==="
    (cd "$REGISTREAM" && uv run --with pyyaml python stata/build/export_package.py --all)
    echo
fi

# Strip macOS metadata before rsync (Finder keeps recreating these)
find "$WEBSITE/data/registream" -name '.DS_Store' -delete 2>/dev/null || true

# Pick rsync mode
if [[ "$DO_APPLY" -eq 1 ]]; then
    DRY_FLAG=""
    MODE="REAL RUN"
else
    DRY_FLAG="-n"
    MODE="DRY RUN (pass --apply to transfer)"
fi

EXCLUDES=(
    --exclude='.DS_Store'
    --exclude='.git/'
    --exclude='__pycache__/'
    --exclude='*.pyc'
)

echo "=== $MODE — target: $REMOTE:$REMOTE_PATH ==="
echo

echo "--- Stata artifacts (data/registream/stata/) ---"
rsync -avz $DRY_FLAG --delete "${EXCLUDES[@]}" \
    "$WEBSITE/data/registream/stata/" \
    "$REMOTE:$REMOTE_PATH/data/registream/stata/"
echo

echo "--- R CRAN repo (data/registream/r/) ---"
rsync -avz $DRY_FLAG --delete "${EXCLUDES[@]}" \
    "$WEBSITE/data/registream/r/" \
    "$REMOTE:$REMOTE_PATH/data/registream/r/"
echo

if [[ "$DO_APPLY" -eq 1 ]]; then
    echo "Artifact sync complete."
    echo
    echo "Code/metadata still pending — pull on the server:"
    echo "  ssh $REMOTE 'cd $REMOTE_PATH && git pull'"
    echo "Then restart the gunicorn process via whatever mechanism the server uses."
else
    echo "Dry-run only. Re-run with --apply to transfer."
fi
