"""Parse nextpnr ECP5 results (structured JSON report + text log).

nextpnr is the source of truth: the ``--report <file>.json`` artefact carries
``fmax`` (achieved per clock), ``utilization`` and ``critical_paths``.  The
text log is parsed as a cross-check (``Max frequency for clock '...'`` and the
device-utilisation table) so a silent change of either format is caught by the
unit tests in ``tests/timing/test_parse.py`` rather than producing silently
wrong numbers.

Nothing here estimates pre-place timing: ``fmax_mhz`` always comes from the
``--report`` produced by a real place-and-route run.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

# nextpnr reports some clocks under this global-network prefix.
_GLOBAL_PREFIX = "$glbnet$"


@dataclass
class CriticalPath:
    source: str
    dest: str
    total_ns: float
    logic_ns: float
    route_ns: float
    segments: int
    types: list[str] = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"{self.source} -> {self.dest} "
            f"[{self.total_ns:.2f} ns: logic {self.logic_ns:.2f} + "
            f"route {self.route_ns:.2f}, {self.segments} segs]"
        )


@dataclass
class NextpnrResult:
    fmax_mhz: float
    constraint_mhz: float
    worst_slack_ns: float
    lut4: int
    ff: int
    ebr18: int
    mult18x18d: int
    pll: int
    ramw: int
    critical_paths: list[CriticalPath]

    @property
    def critical_path_summary(self) -> str:
        if not self.critical_paths:
            return "N/A"
        return self.critical_paths[0].summary()


def _clean_clock(name: str) -> str:
    return name[len(_GLOBAL_PREFIX):] if name.startswith(_GLOBAL_PREFIX) else name


def parse_report(report_text: str) -> NextpnrResult:
    """Parse the JSON produced by ``nextpnr-ecp5 --report``."""
    doc = json.loads(report_text)

    fmax = doc.get("fmax") or {}
    if not fmax:
        raise ValueError("nextpnr report has no 'fmax' section")
    # Worst (lowest) achieved clock dominates the design.
    items = sorted(fmax.items(), key=lambda kv: kv[1]["achieved"])
    clock_name, entry = items[0]
    achieved = float(entry["achieved"])
    constraint = float(entry.get("constraint", 0.0) or 0.0)

    util = doc.get("utilization") or {}
    def used(key: str) -> int:
        return int((util.get(key) or {}).get("used", 0))

    paths = []
    for raw in (doc.get("critical_paths") or []):
        segs = raw.get("path") or []
        if not segs:
            continue
        logic = sum(float(s.get("delay", 0.0)) for s in segs if s.get("type") == "logic")
        route = sum(float(s.get("delay", 0.0)) for s in segs if s.get("type") == "routing")
        source = _clean_clock(segs[0]["from"].get("cell", "?"))
        dest = segs[-1]["to"].get("cell", "?")
        types = sorted({s.get("type", "") for s in segs if s.get("type")})
        paths.append(CriticalPath(
            source=source,
            dest=dest,
            total_ns=logic + route,
            logic_ns=logic,
            route_ns=route,
            segments=len(segs),
            types=types,
        ))

    if constraint > 0:
        worst_slack = 1000.0 / constraint - 1000.0 / achieved if achieved > 0 else float("-inf")
    else:
        worst_slack = float("nan")

    return NextpnrResult(
        fmax_mhz=achieved,
        constraint_mhz=constraint,
        worst_slack_ns=worst_slack,
        lut4=used("TRELLIS_COMB") or used("LUT4"),
        ff=used("TRELLIS_FF"),
        ebr18=used("DP16KD"),
        mult18x18d=used("MULT18X18D"),
        pll=used("EHXPLLL"),
        ramw=used("TRELLIS_RAMW"),
        critical_paths=paths,
    )


_LOG_FMAX = re.compile(
    r"Max frequency for clock '([^']+)':\s*([0-9.]+)\s*MHz\s*"
    r"\((PASS|FAIL) at ([0-9.]+)\s*MHz\)"
)
_LOG_UTIL = re.compile(r"^\s*(?:Info:\s+)?([A-Z0-9_]+):\s*(\d+)\s*/\s*(\d+)\s+\d+%")


def parse_log(log_text: str) -> dict:
    """Parse the human-readable nextpnr log.

    Returns the Fmax line (per clock) and the device-utilisation counters.  It
    deliberately does **not** attempt to reconstruct critical paths from the
    log; those come from the JSON report.
    """
    fmax: dict[str, dict] = {}
    util: dict[str, int] = {}
    for line in log_text.splitlines():
        m = _LOG_FMAX.search(line)
        if m:
            fmax[m.group(1)] = {
                "achieved": float(m.group(2)),
                "constraint": float(m.group(4)),
                "status": m.group(3),
                "clock": _clean_clock(m.group(1)),
            }
            continue
        u = _LOG_UTIL.match(line)
        if u:
            key, used = u.group(1), int(u.group(2))
            # Keep the largest reported count for a key (before/after packing).
            util[key] = max(util.get(key, 0), used)
    return {"fmax": fmax, "utilization": util}


def cross_check(report: NextpnrResult, log_parsed: dict, tol_mhz: float = 0.05) -> list[str]:
    """Return a list of human-readable discrepancies between report and log."""
    problems: list[str] = []
    log_fmax = log_parsed.get("fmax") or {}
    if not log_fmax:
        problems.append("log: no 'Max frequency for clock' line found")
    else:
        best = min(v["achieved"] for v in log_fmax.values())
        if abs(best - report.fmax_mhz) > tol_mhz:
            problems.append(
                f"fmax mismatch: report {report.fmax_mhz:.3f} MHz vs log {best:.3f} MHz"
            )
    log_util = log_parsed.get("utilization") or {}
    for key, val in (("TRELLIS_FF", report.ff), ("DP16KD", report.ebr18),
                     ("MULT18X18D", report.mult18x18d)):
        if key in log_util and log_util[key] != val:
            problems.append(f"util mismatch {key}: report {val} vs log {log_util[key]}")
    return problems
