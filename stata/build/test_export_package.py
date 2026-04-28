"""Unit tests for export_package.py — placeholder substitution and .pkg
generation. Tempfile-based; doesn't run the full build pipeline.

Run:
    cd registream/stata/build
    python -m pytest test_export_package.py -v

Or via uv from the registream-website venv if it has pytest:
    cd registream/stata/build
    uv run --with pytest python -m pytest test_export_package.py -v

These tests cover Phase 4 of version_coordination.md: {{MIN_CORE}}
placeholder substitution and the version-constrained `Requires:` line
in generated .pkg files.
"""

import sys
from pathlib import Path

# Make the build module importable when pytest is invoked from anywhere.
sys.path.insert(0, str(Path(__file__).parent))

import export_package as ep


# ── stamp_file ──────────────────────────────────────────────────────────────


def test_stamp_file_substitutes_version_and_date(tmp_path):
    f = tmp_path / "autolabel.ado"
    f.write_text("*! version {{VERSION}} {{DATE}}\nprogram define autolabel\nend\n")

    ep.stamp_file(str(f), version="3.0.9", release_date="2026-06-15")

    out = f.read_text()
    assert "*! version 3.0.9 2026-06-15" in out
    assert "{{VERSION}}" not in out
    assert "{{DATE}}" not in out


def test_stamp_file_substitutes_min_core(tmp_path):
    f = tmp_path / "autolabel.ado"
    f.write_text(
        "local AUTOLABEL_MIN_CORE \"{{MIN_CORE}}\"\n"
    )
    ep.stamp_file(str(f), version="3.0.9", release_date="2026-06-15", min_core_version="3.0.1")

    out = f.read_text()
    assert "local AUTOLABEL_MIN_CORE \"3.0.1\"" in out
    assert "{{MIN_CORE}}" not in out


def test_stamp_file_min_core_empty_when_unset(tmp_path):
    """For core itself (no min_core_version), the placeholder gets blank."""
    f = tmp_path / "registream.ado"
    f.write_text("local REGISTREAM_MIN_CORE \"{{MIN_CORE}}\"\n")
    ep.stamp_file(str(f), version="3.0.0", release_date="2026-04-08")  # no min_core arg

    out = f.read_text()
    assert "local REGISTREAM_MIN_CORE \"\"" in out


def test_stamp_file_substitutes_sthlp_date(tmp_path):
    f = tmp_path / "autolabel.sthlp"
    f.write_text("{help autolabel:autolabel}{...}\n{ds Updated:}{ds {{STHLP_DATE}}}\n")

    ep.stamp_file(str(f), version="3.0.9", release_date="2026-06-15")

    out = f.read_text()
    assert "15jun2026" in out
    assert "{{STHLP_DATE}}" not in out


def test_stamp_file_idempotent_on_already_stamped_content(tmp_path):
    """Running stamp_file twice should not double-substitute or break."""
    f = tmp_path / "x.ado"
    f.write_text("*! version {{VERSION}}\n")
    ep.stamp_file(str(f), version="3.0.9", release_date="2026-06-15")
    ep.stamp_file(str(f), version="3.0.9", release_date="2026-06-15")
    assert f.read_text() == "*! version 3.0.9\n"


# ── generate_pkg ────────────────────────────────────────────────────────────


def _stub_files(filenames):
    """Build the all_files tuple shape expected by generate_pkg."""
    return [(f, Path("/tmp"), "0.0.0", "2026-01-01") for f in filenames]


def test_generate_pkg_emits_version_constrained_requires(tmp_path):
    cfg = {
        "version": "3.0.9",
        "release_date": "2026-06-15",
        "description": "Automatic variable and value labeling",
        "authors": "Jeffrey Clark, Jie Wen",
        "requires": "registream",
        "min_core_version": "3.0.1",
    }
    ep.generate_pkg("autolabel", cfg,
                    _stub_files(["autolabel.ado", "autolabel.sthlp", "_al_utils.ado"]),
                    tmp_path)

    pkg = (tmp_path / "autolabel.pkg").read_text()
    assert "d Requires: registream (>=3.0.1, install separately)" in pkg
    assert "d Version: 3.0.9" in pkg
    assert "f autolabel.ado" in pkg


def test_generate_pkg_falls_back_to_unversioned_requires(tmp_path):
    """If min_core_version is absent, emit the legacy unversioned form
    (preserves backward-compat for any package without a declared floor)."""
    cfg = {
        "version": "1.0.0",
        "release_date": "2026-04-22",
        "description": "Synthetic data",
        "authors": "Jeffrey Clark",
        "requires": "registream",
        # no min_core_version
    }
    ep.generate_pkg("datamirror", cfg, _stub_files(["datamirror.ado"]), tmp_path)
    pkg = (tmp_path / "datamirror.pkg").read_text()
    assert "d Requires: registream (install separately)" in pkg


def test_generate_pkg_no_requires_when_no_dependency(tmp_path):
    """Core has no `requires` field — no Requires: line at all."""
    cfg = {
        "version": "3.0.0",
        "release_date": "2026-04-08",
        "description": "Core",
        "authors": "Jeffrey Clark",
    }
    ep.generate_pkg("registream", cfg, _stub_files(["registream.ado"]), tmp_path)
    pkg = (tmp_path / "registream.pkg").read_text()
    assert "Requires:" not in pkg


# ── packages.json declares min_core_version ─────────────────────────────────


def test_packages_json_has_min_core_for_modules():
    """Sanity check: packages.json declares min_core_version for modules
    so the build doesn't silently emit unversioned Requires: lines."""
    pkgs = ep.load_packages()
    assert pkgs["autolabel"]["min_core_version"]
    assert pkgs["datamirror"]["min_core_version"]
    # Core itself doesn't need this field
    assert "min_core_version" not in pkgs["registream"]


# ── sync_from_manifest (Phase 5: manifest is canonical for version data) ────


def test_sync_from_manifest_overrides_version_and_date(monkeypatch, tmp_path):
    """The manifest YAML wins over packages.json for version + release_date.
    Static fields (source, files, description, authors) stay untouched."""
    # Stand up a fake manifest at the location sync_from_manifest reads.
    fake_website = tmp_path / "registream-website"
    manifest_dir = fake_website / "data" / "registream"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "package_manifest.yaml").write_text(
        "schema_version: 1\n"
        "packages:\n"
        "  autolabel:\n"
        "    role: module\n"
        "    latest: '3.0.9'\n"
        "    versions:\n"
        "      '3.0.9':\n"
        "        released: '2026-06-15'\n"
        "        requires: { registream: '>=3.0.1' }\n"
    )
    # Point REPO_ROOT.parent at the temp parent so manifest_path resolves to the fake.
    monkeypatch.setattr(ep, "REPO_ROOT", tmp_path / "registream")

    packages = {
        "autolabel": {
            "version": "3.0.0",            # stale
            "release_date": "2026-01-01",  # stale
            "min_core_version": "1.0.0",   # stale
            "source": "../../../autolabel/stata/src",
            "files": ["autolabel.ado"],
            "description": "Autolabel",
            "authors": "Jeffrey Clark",
            "requires": "registream",
        }
    }
    ep.sync_from_manifest(packages)

    assert packages["autolabel"]["version"] == "3.0.9"
    assert packages["autolabel"]["release_date"] == "2026-06-15"
    assert packages["autolabel"]["min_core_version"] == "3.0.1"
    # Static fields untouched
    assert packages["autolabel"]["files"] == ["autolabel.ado"]
    assert packages["autolabel"]["description"] == "Autolabel"
    assert packages["autolabel"]["source"] == "../../../autolabel/stata/src"


def test_sync_from_manifest_silent_when_manifest_missing(monkeypatch, tmp_path, capsys):
    """If the website repo isn't checked out next to registream, sync
    is a no-op + prints a warning. packages.json values stay as-is."""
    monkeypatch.setattr(ep, "REPO_ROOT", tmp_path / "registream")  # no website sibling

    packages = {"autolabel": {"version": "3.0.0", "release_date": "2026-01-01"}}
    ep.sync_from_manifest(packages)

    assert packages["autolabel"]["version"] == "3.0.0"  # unchanged
    out = capsys.readouterr().out
    assert "manifest not found" in out


def test_sync_from_manifest_skips_unknown_packages(monkeypatch, tmp_path):
    """Packages in packages.json but not in manifest are left alone (no
    crash, no override)."""
    fake_website = tmp_path / "registream-website"
    manifest_dir = fake_website / "data" / "registream"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "package_manifest.yaml").write_text(
        "packages:\n"
        "  autolabel:\n"
        "    latest: '3.0.9'\n"
        "    versions: { '3.0.9': { released: '2026-06-15' } }\n"
    )
    monkeypatch.setattr(ep, "REPO_ROOT", tmp_path / "registream")

    packages = {
        "registream": {"version": "3.0.0", "release_date": "2026-04-12"},  # NOT in manifest
        "autolabel":  {"version": "3.0.0", "release_date": "2026-04-12"},  # IS in manifest
    }
    ep.sync_from_manifest(packages)

    assert packages["registream"]["version"] == "3.0.0"  # untouched
    assert packages["autolabel"]["version"] == "3.0.9"   # synced


# ── generate_zip ────────────────────────────────────────────────────────────


def test_generate_zip_creates_archive_with_top_level_folder(tmp_path):
    """Zip should match the legacy convention: top-level folder
    <pkg>_<ver>-stata/ containing the per-package files."""
    import zipfile

    src = tmp_path / "src"
    src.mkdir()
    (src / "stata.toc").write_text("v 3\np autolabel (v3.0.9)\n")
    (src / "autolabel.pkg").write_text("v 3\nf autolabel.ado\n")
    (src / "autolabel.ado").write_text("*! version 3.0.9\n")

    out_base = tmp_path / "out"
    out_base.mkdir()

    cfg = {"version": "3.0.9"}
    ep.generate_zip("autolabel", cfg, src, out_base)

    zpath = out_base / "autolabel_3.0.9-stata.zip"
    assert zpath.exists()

    with zipfile.ZipFile(zpath) as zf:
        names = zf.namelist()
    assert "autolabel_3.0.9-stata/stata.toc" in names
    assert "autolabel_3.0.9-stata/autolabel.pkg" in names
    assert "autolabel_3.0.9-stata/autolabel.ado" in names


def test_generate_zip_overwrites_existing(tmp_path):
    """Re-running the build should replace the old zip cleanly."""
    import zipfile

    src = tmp_path / "src"; src.mkdir()
    (src / "f1.ado").write_text("first")
    out = tmp_path / "out"; out.mkdir()

    ep.generate_zip("autolabel", {"version": "3.0.9"}, src, out)

    # Add another file and re-zip
    (src / "f2.ado").write_text("second")
    ep.generate_zip("autolabel", {"version": "3.0.9"}, src, out)

    with zipfile.ZipFile(out / "autolabel_3.0.9-stata.zip") as zf:
        assert "autolabel_3.0.9-stata/f1.ado" in zf.namelist()
        assert "autolabel_3.0.9-stata/f2.ado" in zf.namelist()


def test_sync_handles_constraint_without_floor(monkeypatch, tmp_path):
    """A `requires` constraint without `>=` (e.g., bare equality or empty)
    leaves min_core_version untouched rather than crashing."""
    fake_website = tmp_path / "registream-website"
    manifest_dir = fake_website / "data" / "registream"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "package_manifest.yaml").write_text(
        "packages:\n"
        "  autolabel:\n"
        "    latest: '3.0.9'\n"
        "    versions:\n"
        "      '3.0.9':\n"
        "        released: '2026-06-15'\n"
        "        requires: { registream: '3.0.1' }\n"   # bare version, no >=
    )
    monkeypatch.setattr(ep, "REPO_ROOT", tmp_path / "registream")

    packages = {"autolabel": {"version": "3.0.0", "min_core_version": "2.0.0"}}
    ep.sync_from_manifest(packages)

    # Version still synced; min_core_version untouched (we don't try to
    # parse non-`>=` constraints).
    assert packages["autolabel"]["version"] == "3.0.9"
    assert packages["autolabel"]["min_core_version"] == "2.0.0"
