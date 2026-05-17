# RegiStream Core Changelog

This file tracks ecosystem-level core releases. Per-language details live in:

- R port: [`r/NEWS.md`](r/NEWS.md)
- Stata port: tracked here under each version's "Stata" section.
- Python port: tracked here under each version's "Python" section.

## v3.0.1 (2026-05-08)

R port only.

R-port patch fixing `parse_value_labels_stata(type = "character")` so it filters integer-coded entries when the metadata mixes integer and string codes (e.g. SCB's CIVIL with both numeric "1"/"2" and Swedish "OG"/"G"/"S" pointing to the same labels). Without this, applying labels to a character column with the mixed metadata triggered `haven::labelled()`'s `labels must be unique` error. See [`r/NEWS.md`](r/NEWS.md) for full details.

## v3.0.0 (2026-04-08)

First release as a modular ecosystem (split from monorepo).

### Architecture

- **Modular ecosystem**: registream is now core infrastructure. Domain-specific functionality lives in separate packages (autolabel, datamirror).
- **One-way dependencies**: Modules depend on core. Core never depends on modules.
- **Independent versioning**: Each package has its own version and release cycle.
- **Per-module heartbeat**: Update checks report all installed module versions to the server and receive per-package update status.

### Changes from v2.0.2

- **Config format**: `config_stata.yaml` replaced with `config_stata.csv` (key;value format, native Stata I/O, no YAML parser needed).
- **Dataset management removed from core**: `scan_datasets`, `check_datasets_bulk`, `update_datasets_interactive` moved to autolabel.
- **Schema validation removed from core**: `_rs_validate_schema.ado` moved to autolabel.
- **Heartbeat rewrite**: Single `send_heartbeat` function handles telemetry and update checking. Removed redundant `check_background`.
- **Cross-platform networking**: All HTTP calls use native Stata `copy` (no `shell curl`).
- **Data directory**: `~/.registream/autolabel_keys/` renamed to `~/.registream/autolabel/`.

### Bug Fixes

- Heartbeat version comparison now uses proper semver (client ahead of server no longer triggers false positive).
- `send_heartbeat` respects `internet_access=false` (previously ignored).
