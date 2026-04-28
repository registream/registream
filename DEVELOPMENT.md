# RegiStream Architecture

RegiStream is a modular ecosystem for research data infrastructure. It follows a **core + modules** pattern:

- **registream** (core) — config, telemetry, update checking, shared utilities
- **autolabel** (module) — automatic variable and value labeling from metadata
- **datamirror** (module) — checkpoint-constrained synthetic data generation

Modules depend on core. Core never depends on modules. Modules never depend on each other.

All three clients (Stata, Python, R) share the same metadata cache at `~/.registream/` and the same server API at `registream.org`.

## Repository Layout

```
registream-org/                    (sibling-clone convention)
├── registream/                    this repo (core)
│   ├── stata/src/                 Stata core (.ado files)
│   ├── stata/tests/               Stata test dofiles
│   ├── stata/build/               Stata packaging
│   ├── python/registream-core/    Python core (pip install registream-core)
│   ├── python/registream-meta/    Metapackage (pip install registream)
│   ├── r/                         R core (CRAN: registream)
│   └── docs/                      Language-specific guides
├── autolabel/                     module repo
│   ├── stata/src/
│   ├── python/registream-autolabel/
│   ├── r/                         CRAN: autolabel
│   └── examples/lisa.dta
└── datamirror/                    module repo
    └── …
```

## One-Way Dependencies

```
autolabel  → depends on → registream core
datamirror → depends on → registream core
autolabel  ✗ never      → datamirror
registream ✗ never      → any module
```

## Shared Cache

```
~/.registream/
├── config_stata.csv          Stata preferences
├── config_python.toml        Python preferences
├── config_r.toml             R preferences (when shared-cache opt-in)
├── usage_stata.csv           Stata command log
├── usage_python.csv          Python command log
├── usage_r.csv               R command log
├── .salt                     Shared user ID hash salt
└── autolabel/
    ├── datasets.csv          Version tracking (all clients)
    └── {domain}/             One folder per metadata domain
        ├── manifest_{lang}.csv
        ├── variables_{lang}.csv|dta
        ├── value_labels_{lang}.csv|dta
        ├── scope_{lang}.csv|dta
        └── release_sets_{lang}.csv|dta
```

R is opt-in for the shared cache (CRAN-sanctioned consent prompt on
first run); the alternative is the per-platform `R_user_dir`.

## Language Guides

- **[Stata](docs/stata.md)** — commands, module integration pattern, build system
- **[Python](docs/python.md)** — distributions, accessor API, publishing
