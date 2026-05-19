# registream

Meta-package for the RegiStream Python ecosystem. One install gets the full
stack; matches the Stata `net install registream` convention.

Full documentation: **<https://registream.org/docs>**.

## Install

```
pip install registream
```

Requires Python 3.11 or later. Installs:

- [`registream-core`](https://pypi.org/project/registream-core/): shared
  config, citation, metadata cache, schema validator, first-run wizard.
- [`registream-autolabel`](https://pypi.org/project/registream-autolabel/):
  pandas accessor + monkey-patched shortcuts for applying variable and value
  labels from the RegiStream catalog.

Future modules (`registream-datamirror` and beyond) will be added as
dependencies of this meta-package as they ship, so a single `pip install
--upgrade registream` always leaves you on the current ecosystem loadout.

## Quick start

```python
import pandas as pd
import registream.autolabel  # side effect: installs autolabel methods on pd.DataFrame

df = pd.read_stata("lisa_2020.dta")
df.autolabel(domain="scb", lang="eng")
df.lab.head()
```

Full API reference, arguments, worked examples, and institutional-setup
guide: <https://registream.org/docs/autolabel/python>.

## What this package contains

Nothing by itself. It's a zero-code metapackage whose only purpose is to
pull in `registream-core` and `registream-autolabel` at compatible versions.
All user-facing code lives in those two packages.

Install them directly if you'd rather not pull the metapackage:

```
pip install registream-core         # just the shared primitives
pip install registream-autolabel    # labeling (pulls core as a dep)
```

## Command-line

Both subpackages expose `python -m` entry points:

```
python -m registream {version,info,cite}
python -m registream.autolabel {version,info,cite}
```

## Citation

```
Clark, J. & Wen, J. (2024). RegiStream: Infrastructure for Register Data Research. https://registream.org
```

## Authors

- Jeffrey Clark — <jeffrey@registream.org>
- Jie Wen — <jie@registream.org>

## License

MIT.
