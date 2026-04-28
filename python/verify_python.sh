#!/usr/bin/env bash
# =============================================================================
# Verify the RegiStream Python ecosystem in a throwaway environment.
# =============================================================================
#
# Three modes:
#
#   ./verify_python.sh
#     Build all three wheels locally (uv build), run import + version
#     checks against the freshly-built wheels in an ephemeral env.
#     Catches the "wheel uploads but doesn't import" class of bugs without
#     touching any package index. Run this BEFORE publishing.
#
#   ./verify_python.sh --from-testpypi
#     Skip the local build. Run import + version checks pulling all three
#     packages from TestPyPI. Transitive deps (pandas, pyreadstat, etc.)
#     resolve against real PyPI (uv adds testpypi as an additional index;
#     pypi.org stays default). Run AFTER publish.sh --testpypi for all three.
#
#   ./verify_python.sh --from-pypi
#     Same shape, but pulls from real PyPI. Smoke test post-publish.
#
# Layout assumption: this script lives at registream/python/verify_python.sh
# and the three module repos are cloned as siblings under one parent dir
# (the registream-org/ convention).
# =============================================================================

set -euo pipefail

# ─── Argument parsing ────────────────────────────────────────────────────────
mode="local"
for arg in "$@"; do
    case "$arg" in
        --from-testpypi) mode="testpypi" ;;
        --from-pypi)     mode="pypi" ;;
        -h|--help)
            sed -n '2,/^# ===/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$arg'" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv not found on PATH." >&2
    exit 1
fi

# ─── Resolve package directories (sibling-clone layout) ──────────────────────
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repos_root="$(cd "$script_dir/../.." && pwd)"

CORE_DIR="$repos_root/registream/python/registream-core"
AUTOLABEL_DIR="$repos_root/autolabel/python/registream-autolabel"
META_DIR="$repos_root/registream/python/registream-meta"

for d in "$CORE_DIR" "$AUTOLABEL_DIR" "$META_DIR"; do
    if [ ! -f "$d/pyproject.toml" ]; then
        echo "ERROR: $d/pyproject.toml not found." >&2
        echo "Expected sibling-clone layout under $repos_root" >&2
        exit 1
    fi
done

# ─── Mode-specific setup ─────────────────────────────────────────────────────
UV_RUN_ARGS=(--no-project)

case "$mode" in
    local)
        echo "==> Building all 3 wheels (uv build)"
        for d in "$CORE_DIR" "$AUTOLABEL_DIR" "$META_DIR"; do
            (cd "$d" && rm -rf dist/ && uv build --quiet)
        done

        # Resolve to single wheel paths (latest one if multiple)
        CORE_WHL=$(ls -t "$CORE_DIR"/dist/*.whl | head -1)
        AUTOLABEL_WHL=$(ls -t "$AUTOLABEL_DIR"/dist/*.whl | head -1)
        META_WHL=$(ls -t "$META_DIR"/dist/*.whl | head -1)

        UV_RUN_ARGS+=(
            --with "$CORE_WHL"
            --with "$AUTOLABEL_WHL"
            --with "$META_WHL"
        )
        echo "==> Verifying built wheels in ephemeral env"
        ;;

    testpypi)
        # --index adds testpypi as an extra index (pypi.org stays default).
        # --index-strategy unsafe-best-match lets uv compare versions across
        # both indexes; without it, "first index wins" (uv's default
        # dependency-confusion guard) pins transitive deps like pandas to
        # whatever stale version testpypi happens to have.
        UV_RUN_ARGS+=(
            --index "https://test.pypi.org/simple/"
            --index-strategy unsafe-best-match
            --with "registream"
            --with "registream-core"
            --with "registream-autolabel"
        )
        echo "==> Verifying TestPyPI install in ephemeral env"
        ;;

    pypi)
        UV_RUN_ARGS+=(
            --with "registream"
            --with "registream-core"
            --with "registream-autolabel"
        )
        echo "==> Verifying real PyPI install in ephemeral env"
        ;;
esac

# ─── Run checks ──────────────────────────────────────────────────────────────
uv run "${UV_RUN_ARGS[@]}" python - <<'PYEOF'
import sys
import importlib.metadata as md

errors = []

# 1. Top-level imports
for pkg in ("registream", "registream.autolabel"):
    try:
        __import__(pkg)
        print(f"  import {pkg:<25} OK")
    except Exception as e:
        errors.append(f"import {pkg}: {e!r}")
        print(f"  import {pkg:<25} FAIL: {e!r}")

# 2. Distribution metadata — each PyPI dist must report a 3.x version
for dist_name in ("registream", "registream-core", "registream-autolabel"):
    try:
        v = md.version(dist_name)
        print(f"  version {dist_name:<25} {v}")
        if not v.startswith("3."):
            errors.append(f"{dist_name} unexpected version: {v}")
    except md.PackageNotFoundError:
        errors.append(f"version {dist_name}: not installed")
        print(f"  version {dist_name:<25} NOT INSTALLED")

# 3. Namespace package shape: registream.autolabel must be contributed
#    by the registream-autolabel distribution (PEP 420 namespace).
try:
    import registream.autolabel as al
    assert hasattr(al, "__file__") or hasattr(al, "__path__"), \
        "registream.autolabel has no __file__/__path__"
    print(f"  registream.autolabel namespace package OK")
except Exception as e:
    errors.append(f"namespace check: {e!r}")
    print(f"  registream.autolabel namespace FAIL: {e!r}")

if errors:
    print()
    print("FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print()
print("All checks passed.")
PYEOF

echo
echo "==> Done. Mode: $mode"
