"""Stata-parity test 07: update default behavior.

Mirror of: ``registream/stata/tests/dofiles/07_update_default_behavior.do``

Three sub-tests in Stata:

1. ``registream update`` (no args) → defaults to package check
2. ``registream update package`` → explicit package check
3. ``registream update dataset`` → errors with rc=198 directing to autolabel

**Python checkpoint 8 cleanup (2026-04-10):** the ``update()`` dispatcher
and ``update_dataset()`` stub were dropped from ``registream.updates`` as
Stata-shaped baggage (per the Stata-baggage audit on 2026-04-09, documented
in ``project_stata_baggage_audit.md``). Python's public API is
``update_package()`` directly; there's no ``registream update [target]``
CLI in Python, so the dispatcher added no value. Sub-tests 1 and 2 now
test ``update_package()`` directly. Sub-test 3 is skipped because the
"dataset" target concept doesn't exist in Python core; dataset updates
live in ``registream.autolabel.update_datasets()`` and are tested there.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from registream.config import Config, save
from registream.updates import HeartbeatResult, update_package


# ─── Test 1/3: update defaults to package check ─────────────────────────────


def test_parity_07_update_package_default(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """Stata: ``registream update`` (no args) defaults to package check.

    Python: ``update_package()`` is the direct equivalent (no dispatcher
    needed; Python doesn't have a CLI ``registream update [target]`` command).
    """
    save(Config(internet_access=True, last_update_check=None), tmp_path)
    result = update_package(version="3.0.0", directory=tmp_path)
    assert isinstance(result, HeartbeatResult)
    assert result.reason in {"success", "cached"}


# ─── Test 2/3: update package explicitly ─────────────────────────────────────


def test_parity_07_update_package_explicit(
    tmp_path: Path,
    mock_heartbeat_no_update: None,
) -> None:
    """Stata: ``registream update package`` checks package updates.

    Python: same as sub-test 1; ``update_package()`` is the only entry
    point after the dispatcher was dropped.
    """
    save(Config(internet_access=True, last_update_check=None), tmp_path)
    result = update_package(version="3.0.0", directory=tmp_path)
    assert isinstance(result, HeartbeatResult)


# ─── Test 3/3: update dataset (DROPPED from core) ───────────────────────────


@pytest.mark.skip(
    reason="The ``update()`` dispatcher and ``update_dataset()`` stub were "
    "dropped from Python core on 2026-04-10 as Stata-shaped baggage "
    "(see project_stata_baggage_audit.md). Dataset updates live in "
    "``registream.autolabel.update_datasets()`` and are tested in "
    "``registream-autolabel/tests/test_datasets.py``. There is no "
    "``registream update dataset`` concept in Python core."
)
def test_parity_07_update_dataset_errors_with_autolabel_hint() -> None:
    pass
