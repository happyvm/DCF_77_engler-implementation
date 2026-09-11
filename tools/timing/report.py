"""Build the versionable timing reports from raw nextpnr results.

Outputs under ``reports/timing/``::

    blocks.csv / blocks.md
    subsystems.csv / subsystems.md

Raw per-module results live in ``reports/timing/raw/<module>.json``.  Only
modules with a real post-route measurement appear; nothing is inferred.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

from . import registry

REPORTS = Path(__file__).resolve().parents[2] / "reports" / "timing"
RAW = REPORTS / "raw"

# Per the BEA-37 spec.  FPGA-specific metrics (LUT4/EBR/MULT18X18D) are
# followed by architectural metrics so a future ASIC comparison can read the
# latter without the technology counts.
COLUMNS = [
    "commit", "date", "module", "kind", "target_device", "speed_grade",
    "clock_target_mhz", "fmax_mhz", "worst_slack_ns", "lut4", "ff", "ebr18",
    "mult18x18d", "pll", "latency_cycles", "throughput", "config",
    "critical_path_summary", "seed", "tool_versions",
    "multiplications", "additions", "comparators", "total_cells", "wire_bits",
    "timing_met",
]

_NA = "N/A"


def classify(fmax_mhz: float, kind: str) -> str:
    """Indicative timing-health class for a clk_sys = 125 MHz target.

    The class is an analysis aid only; ``multicycle`` / ``low-rate-control``
    blocks are annotated rather than marked failing when an isolated path is
    slow, because the architecture explicitly allows more than one cycle.
    """
    if kind in ("multicycle", "low-rate-control"):
        base = "architectural-multicycle"
    else:
        base = "single-cycle"
    if fmax_mhz >= 200:
        band = "excellent"
    elif fmax_mhz >= 175:
        band = "very-good"
    elif fmax_mhz >= 150:
        band = "acceptable"
    elif fmax_mhz >= 125:
        band = "weak"
    else:
        band = "failing"
    return f"{band} ({base})"


def _load() -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not RAW.is_dir():
        return out
    for p in sorted(RAW.glob("*.json")):
        rec = json.loads(p.read_text(encoding="utf-8"))
        out[rec["module"]] = rec
    return out


def _row(rec: dict) -> dict:
    arch = rec.get("arch") or {}
    comps = sum(int(arch.get(k, 0)) for k in
                ("comparators_lt", "comparators_le", "comparators_ge",
                 "comparators_gt", "comparators_eq", "comparators_ne"))
    return {
        "commit": rec.get("commit", _NA),
        "date": rec.get("date", _NA),
        "module": rec["module"],
        "kind": rec.get("kind", _NA),
        "target_device": rec.get("target_device", _NA),
        "speed_grade": rec.get("speed_grade", _NA),
        "clock_target_mhz": rec.get("clock_target_mhz", _NA),
        "fmax_mhz": rec.get("fmax_mhz", _NA),
        "worst_slack_ns": rec.get("worst_slack_ns", _NA),
        "lut4": rec.get("lut4", _NA),
        "ff": rec.get("ff", _NA),
        "ebr18": rec.get("ebr18", _NA),
        "mult18x18d": rec.get("mult18x18d", _NA),
        "pll": rec.get("pll", _NA),
        "latency_cycles": rec.get("latency", _NA),
        "throughput": rec.get("throughput", _NA),
        "config": rec.get("config", _NA),
        "critical_path_summary": rec.get("critical_path_summary", _NA),
        "seed": rec.get("seed", _NA),
        "tool_versions": rec.get("tool_versions", _NA),
        "multiplications": arch.get("multiplications", _NA),
        "additions": arch.get("additions", _NA),
        "comparators": comps if arch else _NA,
        "total_cells": arch.get("total_cells", _NA),
        "wire_bits": arch.get("wire_bits", _NA),
        "timing_met": rec.get("timing_met", _NA),
    }


def _write_csv(rows: list[dict], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, _NA) for c in COLUMNS})


def _md_table(rows: list[dict], cols: list[str]) -> str:
    lines = ["| " + " | ".join(cols) + " |",
             "|" + "|".join("---" for _ in cols) + "|"]
    for r in rows:
        lines.append("| " + " | ".join(str(r.get(c, _NA)) for c in cols) + " |")
    return "\n".join(lines)


def _health_section(recs: list[dict]) -> str:
    lines: list[str] = []
    lines.append("## Timing health (indicative, clk_sys = 125 MHz)\n")
    lines.append("Bands: >=200 excellent, 175-200 very-good, 150-175 acceptable, "
                 "125-150 weak, <125 failing.  Multicycle / low-rate-control blocks "
                 "are annotated, not failed, on an isolated slow path.\n")
    order = {"failing": 0, "weak": 1, "acceptable": 2, "very-good": 3, "excellent": 4}
    for rec in sorted(recs, key=lambda r: (order.get(classify(r["fmax_mhz"], r["kind"]).split()[0], 9),
                                           r["fmax_mhz"])):
        cls = classify(rec["fmax_mhz"], rec["kind"])
        lines.append(f"- `{rec['module']}`: {rec['fmax_mhz']:.1f} MHz — {cls}")
    return "\n".join(lines)


def _critical_path_section(recs: list[dict]) -> str:
    lines = ["## Critical paths (post-route, per block)\n"]
    for rec in sorted(recs, key=lambda r: r["fmax_mhz"]):
        lines.append(f"### {rec['module']} — {rec['fmax_mhz']:.1f} MHz "
                     f"({rec['kind']})\n")
        cps = rec.get("critical_paths") or []
        if not cps:
            lines.append("No critical path reported.\n")
            continue
        for i, cp in enumerate(cps[:5], 1):
            lines.append(f"{i}. `{cp['source']}` -> `{cp['dest']}` "
                         f": {cp['total_ns']:.2f} ns "
                         f"(logic {cp['logic_ns']:.2f} + route {cp['route_ns']:.2f}, "
                         f"{cp['segments']} segs)")
        lines.append("")
    return "\n".join(lines)


def _summary_section(recs: list[dict]) -> str:
    if not recs:
        return "## Summary\n\nNo measurements yet.\n"
    lines = ["## Summary\n"]
    slowest = sorted(recs, key=lambda r: r["fmax_mhz"])[:10]
    lines.append("### 10 slowest blocks\n")
    for r in slowest:
        lines.append(f"- `{r['module']}`: {r['fmax_mhz']:.1f} MHz ({r['kind']})")
    lines.append("\n### Largest LUT consumers\n")
    for r in sorted(recs, key=lambda r: -int(r.get("lut4") or 0))[:10]:
        lines.append(f"- `{r['module']}`: {r['lut4']} LUT4")
    lines.append("\n### Largest DSP consumers\n")
    for r in sorted(recs, key=lambda r: -int(r.get("mult18x18d") or 0))[:10]:
        lines.append(f"- `{r['module']}`: {r['mult18x18d']} MULT18X18D")
    lines.append("\n### Largest RAM consumers\n")
    for r in sorted(recs, key=lambda r: -int(r.get("ebr18") or 0))[:10]:
        lines.append(f"- `{r['module']}`: {r['ebr18']} EBR18")
    return "\n".join(lines)


def generate() -> None:
    data = _load()
    REPORTS.mkdir(parents=True, exist_ok=True)

    # ---- blocks ----
    block_recs = [data[b.module] for b in registry.BLOCKS if b.module in data]
    block_rows = [_row(r) for r in block_recs]
    _write_csv(block_rows, REPORTS / "blocks.csv")
    md = ["# Block timing characterisation (BEA-37)\n",
          "Target: LFE5U-45F-7BG256I speed grade -7, nextpnr-ecp5 --45k, "
          "clk target 125 MHz.\n",
          "Post-route measurements from `nextpnr-ecp5 --report`. "
          "Raw records in `raw/`.\n",
          _md_table(block_rows, ["module", "kind", "fmax_mhz", "worst_slack_ns",
                                 "lut4", "ff", "ebr18", "mult18x18d", "pll"]),
          "", _health_section(block_recs), "",
          _critical_path_section(block_recs), "", _summary_section(block_recs)]
    (REPORTS / "blocks.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    # ---- subsystems ----
    sub_rows = []
    for name, module in registry.SUBSYSTEMS.items():
        if module not in data:
            continue
        r = _row(data[module])
        r["subsystem"] = name
        sub_rows.append(r)
    _write_csv([{**r, "module": r["subsystem"]} for r in sub_rows],
               REPORTS / "subsystems.csv")
    smd = ["# Subsystem timing characterisation (BEA-37)\n",
           "Subsystems map onto the existing RTL integration ladder "
           "(composition modules), so each row is a real post-route measurement "
           "of the composed netlist.\n",
           _md_table(sub_rows, ["subsystem", "module", "kind", "fmax_mhz",
                                "worst_slack_ns", "lut4", "ff", "ebr18",
                                "mult18x18d"]),
           "",
           "## Critical paths\n"]
    for r in sorted(sub_rows, key=lambda x: x["fmax_mhz"]):
        smd.append(f"### {r['subsystem']} ({r['module']}) — {r['fmax_mhz']:.1f} MHz\n")
        for i, cp in enumerate((data[r["module"]].get("critical_paths") or [])[:5], 1):
            smd.append(f"{i}. `{cp['source']}` -> `{cp['dest']}` : "
                       f"{cp['total_ns']:.2f} ns "
                       f"(logic {cp['logic_ns']:.2f} + route {cp['route_ns']:.2f})")
        smd.append("")
    (REPORTS / "subsystems.md").write_text("\n".join(smd) + "\n", encoding="utf-8")


if __name__ == "__main__":  # pragma: no cover
    generate()
    print("reports regenerated")
