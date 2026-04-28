# Python Development Guide

## Distributions

Three PyPI packages share the `registream` namespace via PEP 420:

| Package | Install | Contains |
|---------|---------|----------|
| `registream-core` | `pip install registream-core` | `registream.config`, `registream.updates`, `registream.schema`, etc. |
| `registream-autolabel` | `pip install registream-autolabel` | `registream.autolabel` (in the [autolabel repo](https://github.com/registream/autolabel)) |
| `registream` | `pip install registream` | Metapackage — pulls both |

Each distribution has its own `pyproject.toml`, `uv.lock`, and `.venv/`.

## Dev Setup

```bash
cd registream-org/registream/python/registream-core
uv sync

cd registream-org/autolabel/python/registream-autolabel
uv sync    # links to core via [tool.uv.sources]
```

Cross-module development uses `[tool.uv.sources]` path overrides assuming repos are sibling directories under `registream-org/`.

## API Overview

```python
import pandas as pd
import registream.autolabel

# Download metadata cache
from registream.autolabel import update_datasets
update_datasets("scb", "eng")

# Apply labels
df = pd.read_stata("my_data.dta")
df.autolabel(domain="scb", lang="eng")

# Inspect
df.variable_labels()          # {"age": "Age in years", ...}
df.value_labels()             # {"sex": {1: "Male", 2: "Female"}, ...}
df.rs.lab.head()              # Display with labels (no mutation)
df.rs.lookup("kon")           # Variable metadata lookup
```

Labels are stored in `df.attrs["registream"]`. The DataFrame columns are not mutated.

## Core Modules

| Module | Purpose |
|--------|---------|
| `registream.config` | TOML config at `~/.registream/config_python.toml` |
| `registream.updates` | Heartbeat telemetry, PyPI update check, version compare |
| `registream.usage` | Local CSV logging (`usage_python.csv`) |
| `registream.schema` | Schema 1.0/2.0 validation |
| `registream.metadata` | Shared cache reader (DTA via pyreadstat, CSV fallback) |
| `registream.dirs` | `~/.registream/` resolution |
| `registream.citation` | Citation text |
| `registream.info` | Configuration display |
| `registream.first_run` | Interactive setup wizard |

## Autolabel Modules

| Module | Purpose |
|--------|---------|
| `registream.autolabel._accessor` | `df.rs` accessor (autolabel, lookup, lab) |
| `registream.autolabel._labels` | Variable + value label application |
| `registream.autolabel._lookup` | Variable metadata lookup |
| `registream.autolabel._datasets` | Downloader, `datasets.csv` registry, update check |
| `registream.autolabel._inference` | Register inference from column names |
| `registream.autolabel._filters` | Register/variant/version filter pipeline |
| `registream.autolabel._repr` | `LabeledView` for `df.rs.lab.head()` |
| `registream.autolabel._shortcuts` | Monkey-patch `df.autolabel()` → `df.rs.autolabel()` |

## Notifications

On `df.autolabel()`, after applying labels:

1. Logs full command to `usage_python.csv`
2. Sends batch telemetry via heartbeat POST (24h cache)
3. Checks PyPI for newer package versions
4. Checks registream.org for newer metadata versions
5. Warns user via `warnings.warn()` if updates available

All non-fatal — labeling works regardless.

## Tests

```bash
cd python/registream-core && uv run pytest tests/       # 252 tests
cd python/registream-autolabel && uv run pytest tests/  # 260 tests (from autolabel repo)
```

Parity tests mirror every Stata dofile: `test_parity_01_*.py` through `test_parity_30_*.py`.

## Publish

```bash
./python/publish.sh registream-core          # prompts for PyPI token
./python/publish.sh registream-autolabel     # (run from autolabel repo)
./python/publish.sh registream               # metapackage
```

Token is entered interactively at every run. Never stored on disk.

## Namespace Rule

**Never create `registream/__init__.py`** in any distribution. PEP 420 namespace packaging requires the top-level `registream/` directory to have NO `__init__.py`. Subpackages (`registream/autolabel/__init__.py`) do have their own. Each repo has `check_namespace.sh` to guard this.
