# Stata Development Guide

## Commands

```stata
registream info                          Display configuration and settings
registream config [, options]            View or edit configuration
registream update                        Check for package updates
registream version                       Show installed version
registream cite                          Display citation for publications
registream stats                         View local usage statistics
```

## Dev Setup

1. Clone repos as siblings under `registream-org/`
2. Add both source dirs to Stata's adopath:

```stata
adopath ++ "/path/to/registream-org/registream/stata/src"
adopath ++ "/path/to/registream-org/autolabel/stata/src"
```

3. Activate dev helpers as needed (all live under `registream/stata/dev/`):

```stata
do "/path/to/registream-org/registream/stata/dev/host_override.do"   // point at localhost:5000
do "/path/to/registream-org/registream/stata/dev/auto_approve.do"    // batch mode — no interactive prompts
```

## Config System

Single CSV file at `~/.registream/config_stata.csv` with `key;value` format:

```stata
_rs_config get "`registream_dir'" "my_setting"
_rs_config set "`registream_dir'" "my_setting" "my_value"
```

Module-specific keys are prefixed with the module name (e.g., `datamirror_min_cell_size`).

## Module Integration Pattern

Every Stata module integrates with core like this:

```stata
program define mymodule
    version 16.0

    * 1. Set module version global
    global RS_MYMODULE_VERSION "1.0.0"

    * 2. Get core directory and initialize config
    _rs_utils get_dir
    local registream_dir "`r(dir)'"
    _rs_config init "`registream_dir'"

    * 3. Log usage
    _rs_usage log "`registream_dir'" `"mymodule `0'"' "mymodule" "$RS_MYMODULE_VERSION" "`version'"

    * ... do module work ...

    * 4. Send heartbeat + show notifications
    cap qui _rs_updates send_heartbeat "`registream_dir'" "`version'" "mymodule `0'"
    _rs_updates show_notification "`version'"
end
```

## Distribution

| Channel | Command |
|---------|---------|
| registream.org (canonical) | `net install registream, from("https://registream.org/install/stata/latest") replace` |
| SSC (discovery) | `ssc install registream` |

Both packages served from the same URL. Each has its own `.pkg` file.

## Build

```bash
python3 stata/build/export_package.py --all
```

Package definitions and versions are in `stata/build/packages.json`.

## Tests

```bash
# From Stata
do stata/tests/run_all_tests.do
```

11 test dofiles covering config, updates, telemetry, version resolution, and timestamp caching.
