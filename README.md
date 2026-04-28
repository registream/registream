# registream

Core infrastructure for the [RegiStream](https://registream.org) ecosystem — configuration, updates, telemetry, and shared utilities for register data packages.

## Quick Start

### Python

```bash
pip install registream
```

```python
import pandas as pd
import registream.autolabel

df = pd.read_stata("my_register_data.dta")
df.autolabel(domain="scb", lang="eng")

df.variable_labels()       # {"age": "Age in years", "sex": "Biological sex", ...}
df.value_labels()          # {"sex": {1: "Male", 2: "Female"}, ...}
df.lab.head()              # Display with labels substituted (no mutation)
df.lookup("kon")           # Look up variable metadata
```

### Stata

```stata
net install registream, from("https://registream.org/install/stata/latest") replace
net install autolabel,  from("https://registream.org/install/stata/latest") replace

use my_register_data, clear
autolabel variables, domain(scb) lang(eng)
autolabel values, domain(scb) lang(eng)
```

### R

```r
# install.packages("remotes")
remotes::install_github("registream/registream", subdir = "r")
remotes::install_github("registream/autolabel",  subdir = "r")
```

```r
library(autolabel)
df <- haven::read_dta("my_register_data.dta")
labelled <- autolabel(df, domain = "scb", lang = "eng")
rs_lookup("kon", domain = "scb", lang = "eng")
rs_lab(labelled)              # display with labels substituted
```

To install just the core:

```bash
pip install registream-core
```

```stata
net install registream, from("https://registream.org/install/stata/latest") replace
```

## Commands

### Python

```python
from registream.autolabel import update_datasets

update_datasets("scb", "eng")               # Download metadata cache
df.autolabel(domain="scb", lang="eng")       # Apply labels
df.lookup("kon")                             # Look up variable metadata
df.lab.head()                                # Labeled display view

from registream.citation import cite
from registream.info import info
print(cite())                                # Citation for publications
print(info())                                # Configuration display
```

Command-line equivalents:

```
python -m registream version                # installed core version
python -m registream info                   # config + cache snapshot
python -m registream cite                   # APA + BibTeX citation
python -m registream.autolabel {version,info,cite}
```

### Stata

```stata
registream info                          Display configuration and settings
registream config [, options]            View or edit configuration
registream update                        Check for package updates
registream version                       Show installed version
registream cite                          Display citation for publications
registream stats                         View local usage statistics
```

## First-Run Setup

On first use, `registream` prompts you to choose a setup mode:

| Mode | Internet | Update checks | Telemetry | Best for |
|------|:---:|:---:|:---:|------|
| **Offline** | No | No | No | Air-gapped / MONA environments |
| **Standard** | Yes | Yes | No | Most users (recommended) |
| **Full** | Yes | Yes | Yes | Help improve RegiStream |

## Modules

RegiStream is a modular ecosystem. The core package provides shared infrastructure; modules provide domain-specific functionality.

| Module | Description | Stata | Python | R |
|--------|-------------|-------|--------|---|
| [autolabel](https://github.com/registream/autolabel) | Variable and value labels from register metadata | `net install autolabel, from("https://registream.org/install/stata/latest") replace` | `pip install registream-autolabel` | `remotes::install_github("registream/autolabel", subdir="r")` |
| [datamirror](https://github.com/registream/datamirror) | Checkpoint-constrained synthetic data | `net install datamirror, from("https://registream.org/install/stata/latest") replace` | coming | coming |

For Python, `pip install registream` installs core + autolabel in one step (meta-package; matches the Stata install-everything UX of `net install registream` followed by `net install autolabel`). Install individual packages with `pip install registream-core` or `pip install registream-autolabel`.

Modules are independent Stata packages from v3.0.0 onward; install only what you need.

Modules depend on the core package.

## Privacy

- **Local logging** (on by default): Commands are logged to `~/.registream/usage_{stata,python,r}.csv`. Never leaves your computer.
- **Telemetry** (off by default): Anonymous usage data sent to help improve RegiStream. Opt-in only.

## For Developers

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture, build system, and contribution guide.

## Citation

```python
from registream.citation import cite
print(cite())
```

```stata
registream cite
```

## Authors

Jeffrey Clark and Jie Wen

## License

BSD 3-Clause. See [LICENSE](LICENSE).
