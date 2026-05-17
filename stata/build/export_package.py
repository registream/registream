#!/usr/bin/env python3
"""
RegiStream Package Builder

Builds Stata packages for the modular RegiStream ecosystem.
Reads package definitions from packages.json, stamps version placeholders,
generates .pkg/.toc files, and copies output to the server directory.

Packaging strategy (SSC-compatible):
    Each package ships ONLY its own files. Modules declare ``requires:
    registream`` in packages.json; the requirement shows up in the .pkg
    description (SSC convention) and is enforced at runtime by each
    module's top-level .ado (``cap findfile _rs_utils.ado`` check).

    net install registream  → core only (7 files)
    net install autolabel   → autolabel only (3 files); runtime errors if
                              core missing with install instructions
    net install datamirror  → datamirror only (4 files); same runtime check

    Decoupling is required for SSC — SSC allows one package per submission
    with no bundling. Also fixes STATA.TRK ownership overlap that the old
    self-contained-bundle scheme produced when users installed modules
    separately.

Usage:
    python build/export_package.py autolabel          # build one package
    python build/export_package.py --all              # build all packages
    python build/export_package.py autolabel --tag    # build + git tag

Run from the registream core repo root:
    cd registream-org/registream
    python build/export_package.py --all
"""

import os
import sys
import re
import json
import shutil
import argparse
import subprocess
from datetime import datetime
from pathlib import Path

# Resolve paths relative to this script
SCRIPT_DIR = Path(__file__).parent.resolve()
REPO_ROOT = SCRIPT_DIR.parent.parent  # registream-org/registream/
BUILD_DIR = SCRIPT_DIR

# Make the tools/ package importable so we can pull citation data from
# the canonical citations.yaml. Falls back to a no-op substitution if the
# module is unavailable (keeps build working for clean clones).
sys.path.insert(0, str(REPO_ROOT))
try:
    from tools import render_citations as _citations
    _raw = _citations.load()
    _CITATIONS_DATA = _citations.as_dict(_raw.get("works", {}))
    _CONTRIBUTORS_DATA = _raw.get("contributors", {})
except Exception as _e:
    _CITATIONS_DATA = {}
    _CONTRIBUTORS_DATA = {}
    print(f"  WARNING: citations.yaml unavailable ({_e!r}); {{CITATION_*}} placeholders will not be substituted")

# Default output: registream-website data directory.
# Per-package layout (Phase 5 of version_coordination.md):
#   <_STATA_BASE>/<pkg>/<version>/{stata.toc, <pkg>.pkg, ...}
# This is a flip from the legacy merged layout (<_STATA_BASE>/<version>/...).
_STATA_BASE = REPO_ROOT.parent / "registream-website" / "data" / "registream" / "stata"
CHANGELOG_OUTPUT = REPO_ROOT.parent / "registream-website" / "data" / "registream" / "changelog.json"


def load_packages():
    """Load package definitions from packages.json, then override version
    fields from the canonical package_manifest.yaml.

    packages.json provides static metadata that doesn't change between
    releases (source path, file list, description, authors). The manifest
    YAML in the website repo provides the per-release values (version,
    release_date, min_core_version) so a single edit there flows through
    to both build artifacts and the heartbeat resolver.

    See registream-docs/architecture/version_coordination.md (Phase 5).
    """
    packages_file = BUILD_DIR / "packages.json"
    with open(packages_file) as f:
        packages = json.load(f)

    sync_from_manifest(packages)
    return packages


def sync_from_manifest(packages):
    """In-place override of version/release_date/min_core_version from
    package_manifest.yaml. No-op if the manifest is unreachable, so this
    stays safe in environments where the website repo isn't checked out
    next to the registream repo.
    """
    manifest_path = (
        REPO_ROOT.parent
        / "registream-website"
        / "data"
        / "registream"
        / "package_manifest.yaml"
    )
    if not manifest_path.exists():
        print(f"  WARNING: manifest not found at {manifest_path}; using packages.json values as-is")
        return

    try:
        import yaml as _yaml
        with open(manifest_path) as f:
            manifest = _yaml.safe_load(f) or {}
    except Exception as e:
        print(f"  WARNING: failed to parse manifest ({e!r}); using packages.json values as-is")
        return

    for pkg_name, pkg_config in packages.items():
        m_pkg = manifest.get("packages", {}).get(pkg_name)
        if not m_pkg:
            continue
        latest = m_pkg.get("latest")
        if not latest:
            continue
        latest_info = m_pkg.get("versions", {}).get(latest, {}) or {}

        # Version + release date
        pkg_config["version"] = latest
        if latest_info.get("released"):
            pkg_config["release_date"] = latest_info["released"]

        # min_core_version comes from the registream constraint
        # (e.g., ">=3.0.1" → "3.0.1"). Only modules have this.
        constraint = (latest_info.get("requires") or {}).get("registream")
        if constraint and constraint.startswith(">="):
            floor = constraint[2:].strip().split(",")[0].strip()
            pkg_config["min_core_version"] = floor


def sthlp_date(release_date_str):
    """Convert YYYY-MM-DD to DDmmmYYYY format for Stata help files"""
    dt = datetime.strptime(release_date_str, "%Y-%m-%d")
    return dt.strftime("%d%b%Y").lower()


def stamp_file(filepath, version, release_date, min_core_version=""):
    """Replace placeholders in a file.

    Substitutes in order:
      1. {{CITATION_<WORK>_<VARIANT>}}  — citation text from citations.yaml
         (may itself contain {{VERSION}} which is resolved in step 2)
      2. {{VERSION}}, {{DATE}}, {{STHLP_DATE}}  — per-package stamps
      3. {{MIN_CORE}}  — min registream-core version (modules only; "" for core)
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Contributor substitutions (affiliation, email).
    for key, contributor in _CONTRIBUTORS_DATA.items():
        k = key.upper()
        content = content.replace(f"{{{{AFFILIATION_{k}}}}}", contributor.get("affiliation", ""))
        content = content.replace(f"{{{{EMAIL_{k}}}}}", contributor.get("email", ""))

    # 2. Citation substitutions (may emit further {{VERSION}} tokens).
    for work_key, variants in _CITATIONS_DATA.items():
        for variant_name, variant_value in variants.items():
            token = f"{{{{CITATION_{work_key.upper()}_{variant_name.upper()}}}}}"
            if token in content:
                content = content.replace(token, str(variant_value))

    # 3. Version / date stamps.
    content = content.replace("{{VERSION}}", version)
    content = content.replace("{{DATE}}", release_date)
    content = content.replace("{{STHLP_DATE}}", sthlp_date(release_date))

    # 4. Min-core constraint (Phase 4 of version_coordination.md). Modules
    # bake this constant into their .ado so the runtime _rs_check_core_version
    # call has a value even when the manifest is unreachable.
    content = content.replace("{{MIN_CORE}}", min_core_version)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)


def resolve_pkg_files(pkg_name, packages):
    """Resolve the file list for a package.

    In the decoupled packaging model, each .pkg ships only its own files.
    The ``requires`` key in packages.json is documentation only — it appears
    as a ``d Requires: …`` line in the .pkg description and is enforced at
    runtime by the module's .ado (``cap findfile _rs_utils.ado``).

    Returns a list of (filename, source_dir, version, release_date) tuples.
    """
    pkg = packages[pkg_name]
    source_dir = (BUILD_DIR / pkg["source"]).resolve()
    return [
        (f, source_dir, pkg["version"], pkg["release_date"])
        for f in pkg["files"]
    ]


def generate_pkg(pkg_name, pkg_config, all_files, output_dir):
    """Generate a .pkg file listing this package's files.

    The ``requires`` key from packages.json (if present) surfaces as a
    ``d Requires: …`` description line — the SSC convention for signalling
    that users must install the prerequisite separately.
    """
    lines = [
        "v 3",
        f"d {pkg_name}: {pkg_config['description']}",
        f"d Author(s): {pkg_config['authors']}",
        "d Requires Stata 16",
    ]

    requires = pkg_config.get("requires")
    if requires:
        # SSC convention: human-readable Requires: line (Stata doesn't
        # enforce). Includes min-version constraint when known.
        min_core = pkg_config.get("min_core_version")
        if min_core:
            lines.append(f"d Requires: {requires} (>={min_core}, install separately)")
        else:
            lines.append(f"d Requires: {requires} (install separately)")

    lines.extend([
        "d",
        f"d Version: {pkg_config['version']}",
        f"d Distribution-Date: {pkg_config['release_date']}",
        "d Support: email support@registream.org",
    ])

    seen = set()
    for filename, _, _, _ in all_files:
        if filename not in seen:
            lines.append(f"f {filename}")
            seen.add(filename)

    pkg_path = output_dir / f"{pkg_name}.pkg"
    with open(pkg_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"  Generated {pkg_name}.pkg ({len(seen)} files)")


def generate_toc(pkg_name, pkg_config, output_dir):
    """Generate a single-package stata.toc inside the package's own folder.

    Phase 5 of version_coordination.md: each <pkg>/<version>/ folder is a
    self-contained `net install` endpoint with one `p` line, not a merged
    multi-package toc.
    """
    desc = pkg_config["description"]
    version = pkg_config["version"]
    lines = [
        "v 3",
        f"d {pkg_name}: {desc}",
        "d Distributed by RegiStream at https://registream.org",
        "d",
        f"p {pkg_name} {desc} (v{version})",
    ]

    toc_path = output_dir / "stata.toc"
    with open(toc_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"  Generated stata.toc")


def build_package(pkg_name, packages, output_base):
    """Build a single package into output_base/<pkg>/<version>/.

    Phase 5 layout: per-package, per-version. Each folder is a complete
    `net install` endpoint (its own stata.toc + <pkg>.pkg + files).
    """
    pkg_config = packages[pkg_name]
    source_dir = (BUILD_DIR / pkg_config["source"]).resolve()
    output_dir = output_base / pkg_name / pkg_config["version"]
    output_dir.mkdir(parents=True, exist_ok=True)

    if not source_dir.exists():
        print(f"  ERROR: Source directory not found: {source_dir}")
        return False

    print(f"\nBuilding {pkg_name} v{pkg_config['version']}...")

    # Resolve all files (own + bundled/required)
    all_files = resolve_pkg_files(pkg_name, packages)

    # Min-core constraint (Phase 4). Modules carry it for runtime check;
    # core itself has no min_core_version (it IS core).
    min_core = pkg_config.get("min_core_version", "")

    # Copy and stamp each file
    seen = set()
    for filename, file_source_dir, version, release_date in all_files:
        if filename in seen:
            continue  # skip duplicate (same file from own + dependency)
        seen.add(filename)

        src = file_source_dir / filename
        dst = output_dir / filename

        if not src.exists():
            print(f"  WARNING: File not found: {src}")
            continue

        shutil.copy2(src, dst)

        # Stamp text files with their own package's version + min-core
        if filename.endswith((".ado", ".sthlp")):
            stamp_file(dst, version, release_date, min_core)

        print(f"  Copied {filename}")

    # Generate .pkg + single-package stata.toc inside this package's folder
    generate_pkg(pkg_name, pkg_config, all_files, output_dir)
    generate_toc(pkg_name, pkg_config, output_dir)

    # Per-package zip for offline / secure-env install (Phase 5).
    # Convention matches legacy: top-level folder <pkg>_<ver>-stata/.
    # Lives in the stata/ root so /get_zip/stata/<pkg>/<ver> can serve it.
    generate_zip(pkg_name, pkg_config, output_dir, output_base)

    return True


def generate_zip(pkg_name, pkg_config, src_dir, output_base):
    """Zip the contents of src_dir into <output_base>/<pkg>_<ver>-stata.zip
    with top-level folder <pkg>_<ver>-stata/ (matches legacy zip layout)."""
    import zipfile
    version = pkg_config["version"]
    zip_name = f"{pkg_name}_{version}-stata"
    zip_path = output_base / f"{zip_name}.zip"
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(src_dir.iterdir()):
            if f.is_file():
                zf.write(f, arcname=f"{zip_name}/{f.name}")
    print(f"  Generated {zip_path.name}")


def parse_changelog(changelog_path):
    """
    Parse a CHANGELOG.md file into structured version entries.

    Expected format:
        # Title
        ## vX.Y.Z (YYYY-MM-DD)
        Description...
        ### Section
        - Item

    Returns list of dicts with: version, date, summary, body (raw markdown).
    """
    if not changelog_path.exists():
        return []

    content = changelog_path.read_text(encoding='utf-8')
    versions = []

    # Split on ## vX.Y.Z headers
    parts = re.split(r'^## v?(\d+\.\d+\.\d+)\s*\((\d{4}-\d{2}-\d{2})\)', content, flags=re.MULTILINE)

    # parts[0] is the preamble (title), then triplets: (version, date, body)
    i = 1
    while i + 2 <= len(parts):
        version = parts[i]
        date = parts[i + 1]
        body = parts[i + 2].strip()

        # Extract first paragraph as summary
        summary_match = re.match(r'^(.+?)(?:\n\n|\n###)', body, re.DOTALL)
        summary = summary_match.group(1).strip() if summary_match else ""

        versions.append({
            "version": version,
            "release_date": date,
            "summary": summary,
            "body": body,
        })
        i += 3

    return versions


def generate_changelog(packages):
    """
    Read CHANGELOG.md from each package repo and generate a combined changelog.json.
    """
    changelog = {}

    for pkg_name, pkg_config in packages.items():
        source_dir = (BUILD_DIR / pkg_config["source"]).resolve()

        # Walk up to find repo root
        repo_dir = source_dir
        while repo_dir != repo_dir.parent:
            if (repo_dir / ".git").exists() or (repo_dir / ".project-root").exists():
                break
            repo_dir = repo_dir.parent

        changelog_path = repo_dir / "CHANGELOG.md"
        versions = parse_changelog(changelog_path)

        if versions:
            changelog[pkg_name] = {
                "current_version": pkg_config["version"],
                "versions": versions,
            }
            print(f"  Parsed {pkg_name} changelog: {len(versions)} version(s)")
        else:
            print(f"  No CHANGELOG.md found for {pkg_name}")

    with open(CHANGELOG_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(changelog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"  Generated {CHANGELOG_OUTPUT.name}")


def tag_repo(pkg_name, pkg_config):
    """Create a git tag in the package's source repo"""
    source_dir = (BUILD_DIR / pkg_config["source"]).resolve()
    # Walk up to find the repo root (directory containing .git)
    repo_dir = source_dir
    while repo_dir != repo_dir.parent:
        if (repo_dir / ".git").exists():
            break
        repo_dir = repo_dir.parent

    if not (repo_dir / ".git").exists():
        print(f"  WARNING: No git repo found for {pkg_name}")
        return

    version = pkg_config["version"]
    tag = f"v{version}"

    result = subprocess.run(
        ["git", "-C", str(repo_dir), "tag", tag],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        print(f"  Tagged {repo_dir.name} as {tag}")
        print(f"  Push with: git -C {repo_dir} push origin {tag}")
    else:
        print(f"  Tag {tag} already exists or error: {result.stderr.strip()}")


def main():
    parser = argparse.ArgumentParser(description="Build RegiStream Stata packages")
    parser.add_argument("package", nargs="?", help="Package name to build (or --all)")
    parser.add_argument("--all", action="store_true", help="Build all packages")
    parser.add_argument("--tag", action="store_true", help="Create git tag after build")
    parser.add_argument("--output", type=Path, default=None,
                        help="Output base directory (default: registream-website data dir). "
                             "Per-package layout writes <output>/<pkg>/<version>/.")
    args = parser.parse_args()

    if not args.package and not args.all:
        parser.print_help()
        sys.exit(1)

    packages = load_packages()

    # Output base; per-package subdirs (<pkg>/<version>/) are made by build_package.
    if args.output is None:
        args.output = _STATA_BASE
    args.output.mkdir(parents=True, exist_ok=True)

    if args.all:
        for pkg_name in packages:
            build_package(pkg_name, packages, args.output)
            if args.tag:
                tag_repo(pkg_name, packages[pkg_name])
    else:
        if args.package not in packages:
            print(f"Unknown package: {args.package}")
            print(f"Available: {', '.join(packages.keys())}")
            sys.exit(1)

        build_package(args.package, packages, args.output)
        if args.tag:
            tag_repo(args.package, packages[args.package])

    # Changelog is derived from each module's CHANGELOG.md and powers the
    # website's /changelog page. Version metadata flows directly from
    # package_manifest.yaml — no separate JSON heartbeat manifest needed.
    generate_changelog(packages)

    print(f"\nBuild complete. Output base: {args.output}")
    print(f"\nInstall commands (per-package URLs — Phase 2 of version_coordination.md):")
    print(f'  net install registream, from("https://registream.org/install/stata/registream/latest") replace')
    print(f'  net install autolabel,  from("https://registream.org/install/stata/autolabel/latest") replace')
    print(f'  net install datamirror, from("https://registream.org/install/stata/datamirror/latest") replace')

    print(f"\nReleasing: rsync the per-package folders under {args.output} to the server's data/registream/stata/.")


if __name__ == "__main__":
    main()
