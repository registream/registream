# registream-core

Core shared primitives for the RegiStream ecosystem: config, citation,
metadata cache, schema validator, telemetry, and the first-run wizard.

This package is **not the user-facing surface**. Most users install
[`registream-autolabel`](https://pypi.org/project/registream-autolabel/)
(which declares this as a dependency) or the meta-package `registream`.
Install `registream-core` directly only when you want the underlying
primitives without the labeling accessor on top.

Full documentation: **<https://registream.org/docs>**.

## Install

```
pip install registream-core
```

Requires Python 3.11 or later.

## Command-line

```
python -m registream version      # installed core version
python -m registream info         # config snapshot + cache directory
python -m registream cite         # project citation (APA + BibTeX)
```

## Python API

```python
from registream.citation import cite, cite_bibtex   # versioned APA / BibTeX
from registream.info import info                    # config + environment snapshot (str)
from registream.metadata import load_bundle         # load a 5-file metadata bundle
from registream.schema import Manifest, SchemaError, SchemaVersionError
```

Every function has a docstring; `help(registream.citation)` (or `?cite` in
Jupyter) returns the reference inline.

## What's in the box

| Module | Role |
|---|---|
| `registream.citation` | Project APA + BibTeX, sourced from the ecosystem-wide `citations.yaml`. |
| `registream.info` | Configuration snapshot (matches Stata `registream info`). |
| `registream.config` | TOML-backed shared config (`~/.registream/config_python.toml`). |
| `registream.metadata` | `LabelBundle` + `load_bundle(domain, lang)`: reads the 5-file schema v2 bundle from disk. |
| `registream.schema` | `Manifest` dataclass, schema-version gating, CSV validators. |
| `registream.dirs` | Platform-appropriate user-data directory resolution. |
| `registream.updates` | Heartbeat + `pip install --upgrade` check (no data beyond version strings). |
| `registream.usage` | Local-only usage log (`usage_python.csv` in the user-data directory). |
| `registream.first_run` | One-time setup wizard (Offline / Standard / Full mode). |

## Citation

```
Clark, J. & Wen, J. (2024). RegiStream: Infrastructure for Register Data Research. https://registream.org
```

`registream.citation.cite()` returns the versioned form; `cite_bibtex()`
returns the BibTeX entry. Both pull their data from
`citations.yaml` in the RegiStream core repo; single source of truth
for all client ports (Stata, Python, R).

## Authors

- Jeffrey Clark — <jeffrey@registream.org>
- Jie Wen — <jie@registream.org>

## License

MIT.
