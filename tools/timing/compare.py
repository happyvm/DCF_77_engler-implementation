"""Compare two timing campaigns (before / after an optimisation).

Reads two directories of raw records (or falls back to the current
``reports/timing/raw``) and prints per-module deltas for the metrics that
matter for a resource/Fmax/latency trade-off.

Example::

    python3 tools/timing/compare.py --before /tmp/before --after /tmp/after
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import registry

_RAW = Path(__file__).resolve().parents[2] / "reports" / "timing" / "raw"


def _load(directory: Path | None) -> dict[str, dict]:
    directory = directory or _RAW
    out: dict[str, dict] = {}
    if directory.is_dir():
        for p in sorted(directory.glob("*.json")):
            rec = json.loads(p.read_text(encoding="utf-8"))
            out[rec["module"]] = rec
    return out


def _fmt(name: str, before: dict, after: dict) -> str:
    lines = [name, ""]
    for label, rec in (("before", before), ("after", after)):
        arch = rec.get("arch") or {}
        lines.append(f"{label}:")
        lines.append(f"  Fmax       {rec['fmax_mhz']:.1f} MHz")
        lines.append(f"  slack      {rec['worst_slack_ns']:.2f} ns")
        lines.append(f"  LUT        {rec['lut4']}")
        lines.append(f"  FF         {rec['ff']}")
        lines.append(f"  EBR        {rec['ebr18']}")
        lines.append(f"  MULT       {rec['mult18x18d']}")
        lines.append(f"  mults      {arch.get('multiplications', 'N/A')} (generic)")
        lines.append(f"  latency    {rec.get('latency', 'N/A')}")
        lines.append(f"  throughput {rec.get('throughput', 'N/A')}")
    d_fmax = after["fmax_mhz"] - before["fmax_mhz"]
    lines.append(f"delta: Fmax {d_fmax:+.1f} MHz, "
                 f"LUT {int(after['lut4']) - int(before['lut4']):+d}, "
                 f"MULT {int(after['mult18x18d']) - int(before['mult18x18d']):+d}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", type=Path, default=None)
    ap.add_argument("--after", type=Path, default=None)
    args = ap.parse_args(argv)
    before = _load(args.before)
    after = _load(args.after)
    common = sorted(set(before) & set(after))
    if not common:
        print("no common modules between the two campaigns")
        return 1
    for name in common:
        print(_fmt(name, before[name], after[name]))
        print()
    only_b = sorted(set(before) - set(after))
    only_a = sorted(set(after) - set(before))
    if only_b:
        print(f"only in before: {', '.join(only_b)}")
    if only_a:
        print(f"only in after : {', '.join(only_a)}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
