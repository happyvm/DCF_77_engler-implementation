#!/usr/bin/env python3
"""Check a Yosys ECP5 JSON netlist against rtl/resource_budget.json."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


CELL_GROUPS = {
    "lut4_equivalent": {"LUT4"},
    "flip_flops": {"TRELLIS_FF"},
    "ebr18_blocks": {"DP16KD"},
    "mult18x18": {"MULT18X18D"},
    "clock_managers": {"EHXPLLL"},
}


def cell_counts(netlist: dict[str, object]) -> Counter[str]:
    """Count cell types in every module retained in a Yosys JSON netlist."""
    counts: Counter[str] = Counter()
    modules = netlist.get("modules", {})
    if not isinstance(modules, dict):
        raise ValueError("netlist has no modules object")
    for module in modules.values():
        if not isinstance(module, dict):
            continue
        cells = module.get("cells", {})
        if not isinstance(cells, dict):
            continue
        for cell in cells.values():
            if isinstance(cell, dict) and isinstance(cell.get("type"), str):
                counts[cell["type"]] += 1
    return counts


def usage_from_counts(counts: Counter[str]) -> dict[str, int]:
    return {
        resource: sum(counts[cell_type] for cell_type in types)
        for resource, types in CELL_GROUPS.items()
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("netlist", type=Path)
    parser.add_argument("--budget", type=Path, default=Path("rtl/resource_budget.json"))
    parser.add_argument("--profile", default="release_reference")
    args = parser.parse_args()

    budget = json.loads(args.budget.read_text())
    profile = budget["profiles"].get(args.profile)
    if profile is None:
        raise SystemExit(f"unknown resource profile: {args.profile}")

    counts = cell_counts(json.loads(args.netlist.read_text()))
    usage = usage_from_counts(counts)
    limits = budget["limits"]
    failed = False
    for resource, used in usage.items():
        limit = limits[resource]
        state = "PASS" if used <= limit else "FAIL"
        print(f"{state:4} {resource:20} {used:8d} / {limit:8d}")
        failed |= used > limit

    # LUT/distributed memory bits cannot be reconstructed reliably from a
    # technology-mapped cell count alone; keep this limitation visible.
    print("INFO distributed_ram_kib requires a dedicated memory report")
    if profile["enforce_limits"] and failed:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
