#!/usr/bin/env bash
# Guards the PEP 420 namespace package invariant for the registream core repo's
# Python distributions. The `registream/` directory shipped by registream-core
# must NOT contain an `__init__.py`; it is a namespace package shared with
# sibling distributions (registream-autolabel, registream-datamirror, ...).
#
# Wire this script into CI for the `registream` core repo.
set -euo pipefail

cd "$(dirname "$0")"

violator="registream-core/src/registream/__init__.py"
if [ -f "$violator" ]; then
    echo "ERROR: $violator exists."
    echo "registream-core must remain a PEP 420 namespace contributor: no top-level __init__.py."
    exit 1
fi

echo "registream-core namespace check OK."
