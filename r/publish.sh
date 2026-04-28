#!/usr/bin/env bash
# publish.sh: build RegiStream R distributions and populate the website
#              CRAN-format repository at registream.org/r/
#
# Usage:
#   ./publish.sh <package> [--check] [--dry-run]
#   ./publish.sh --all     [--check] [--dry-run]
#
# Packages:
#   registream   the core package
#   autolabel    the autolabel module
#
# Flags:
#   --check      run `R CMD check --as-cran` before publishing (CRAN gate)
#   --dry-run    build tarballs only; do not copy to the server directory
#   -h, --help   show this message
#
# Behavior:
#   1. Runs `R CMD build` on the package source tree to produce a
#      `<pkg>_<version>.tar.gz` tarball in a temp staging directory.
#   2. Optionally runs `R CMD check --as-cran` against the tarball and
#      aborts on ERROR or WARNING (environmental NOTEs are tolerated).
#   3. Copies the tarball into
#        registream.org/data/registream/r/src/contrib/
#      and regenerates `PACKAGES` / `PACKAGES.gz` via
#      `tools::write_PACKAGES()`. No `drat` dependency; base R's
#      CRAN-repository tooling is sufficient.
#   4. Prints the install command end users should type.
#
# No credentials needed; the web server serves the static directory
# directly. This script does NOT commit or deploy; the operator can
# `git add/commit/push` after inspecting the diff.
#
# Layout assumption:
#   Repos are cloned as siblings under ~/Github/registream-org/:
#     registream-org/registream/        ← core R package under r/
#     registream-org/autolabel/         ← autolabel R package under r/
#     registream-org/registream.org/    ← the website data/ tree
#   This script lives at registream-org/registream/r/publish.sh and
#   walks up two levels to resolve siblings.

set -euo pipefail

# ─── Help ────────────────────────────────────────────────────────────────────
print_help() {
    sed -n '2,39p' "$0" | sed 's/^# \?//'
}

# ─── Argument parsing ────────────────────────────────────────────────────────
package="${1:-}"
do_check=0
dry_run=0
all=0

if [ -z "$package" ] || [ "$package" = "-h" ] || [ "$package" = "--help" ]; then
    print_help
    [ -z "$package" ] && exit 2 || exit 0
fi
shift

if [ "$package" = "--all" ]; then
    all=1
fi

for arg in "$@"; do
    case "$arg" in
        --check)    do_check=1 ;;
        --dry-run)  dry_run=1 ;;
        -h|--help)  print_help; exit 0 ;;
        *)
            echo "ERROR: unknown argument '$arg'" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

# ─── Sanity: R must be on PATH ───────────────────────────────────────────────
if ! command -v R >/dev/null 2>&1; then
    echo "ERROR: R not found on PATH." >&2
    exit 1
fi

# ─── Resolve paths (sibling-clone layout) ────────────────────────────────────
script_dir="$(cd "$(dirname "$0")" && pwd)"
repos_root="$(cd "$script_dir/../.." && pwd)"

server_dir="$repos_root/registream.org/data/registream/r/src/contrib"
staging_dir="$(mktemp -d -t registream-r-XXXXXX)"
trap 'rm -rf "$staging_dir"' EXIT

resolve_pkg_dir() {
    case "$1" in
        registream) echo "$repos_root/registream/r" ;;
        autolabel)  echo "$repos_root/autolabel/r"  ;;
        *)
            echo "ERROR: unknown package '$1' (valid: registream, autolabel)" >&2
            exit 2
            ;;
    esac
}

packages_to_build=()
if [ "$all" -eq 1 ]; then
    packages_to_build=(registream autolabel)
else
    packages_to_build=("$package")
fi

# ─── Build each package ──────────────────────────────────────────────────────
built_tarballs=()
for pkg in "${packages_to_build[@]}"; do
    pkg_dir="$(resolve_pkg_dir "$pkg")"
    if [ ! -f "$pkg_dir/DESCRIPTION" ]; then
        echo "ERROR: $pkg_dir/DESCRIPTION not found." >&2
        exit 1
    fi

    echo "==> Building $pkg from $pkg_dir"
    (cd "$staging_dir" && R CMD build "$pkg_dir")

    tarball="$(ls -1 "$staging_dir"/"$pkg"_*.tar.gz | head -n1)"
    if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
        echo "ERROR: R CMD build did not produce a tarball for $pkg." >&2
        exit 1
    fi
    echo "    built: $(basename "$tarball")"
    built_tarballs+=("$tarball")

    if [ "$do_check" -eq 1 ]; then
        echo "==> Checking $pkg (R CMD check --as-cran)"
        if ! (cd "$staging_dir" && R CMD check --as-cran --no-manual "$tarball"); then
            echo "ERROR: R CMD check --as-cran failed for $pkg." >&2
            exit 1
        fi
    fi
done

echo

# ─── Dry-run: print and exit ─────────────────────────────────────────────────
if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] Would copy the following to $server_dir:"
    for t in "${built_tarballs[@]}"; do
        echo "  $(basename "$t")  ($(wc -c < "$t") bytes)"
    done
    echo "[dry-run] Would regenerate PACKAGES/PACKAGES.gz."
    exit 0
fi

# ─── Copy to the website repository directory ───────────────────────────────
mkdir -p "$server_dir"
for t in "${built_tarballs[@]}"; do
    cp "$t" "$server_dir/"
    echo "==> copied $(basename "$t") → $server_dir/"
done

# ─── Regenerate PACKAGES index via base R's tools::write_PACKAGES ────────────
echo "==> Regenerating PACKAGES / PACKAGES.gz in $server_dir"
Rscript --vanilla -e "tools::write_PACKAGES('$server_dir', type = 'source')"

echo
echo "==> Done."
echo
echo "End-users install via:"
echo "  install.packages("
echo "    c(\"registream\", \"autolabel\"),"
echo "    repos = c("
echo "      \"https://registream.org/r/\","
echo "      \"https://cloud.r-project.org/\""
echo "    ),"
echo "    type = \"source\""
echo "  )"
echo
echo "Next: commit the new tarballs + PACKAGES files in the registream.org"
echo "repo, push, and confirm the web server serves /r/src/contrib/ as a"
echo "static directory."
