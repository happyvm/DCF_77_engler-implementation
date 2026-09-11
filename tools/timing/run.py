"""BEA-37 timing-characterisation runner.

Usage (normally through the Makefile)::

    python3 tools/timing/run.py block --name frequency_discipline
    python3 tools/timing/run.py subsystem --name goertzel_observables
    python3 tools/timing/run.py all-blocks
    python3 tools/timing/run.py all-subsystems
    python3 tools/timing/run.py profile

Every run really executes Yosys (``synth_ecp5``) and nextpnr-ecp5
(``--45k --package CABGA256``) on the LFE5U-45F-7BG256I target and reads the
post-route ``--report`` JSON.  Any failure (Yosys, nextpnr, parsing, missing
artefact) raises ``CampaignError`` and the process exits non-zero: there is no
silent success.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from . import nextpnr as np
from . import registry
from . import wrapper as wrappergen

REPO = Path(__file__).resolve().parents[2]
BUILD = REPO / "build" / "timing"
SRC_ROOT = BUILD / "src"          # pristine ``git archive HEAD`` export
REPORTS = REPO / "reports" / "timing"
RAW = REPORTS / "raw"

TARGET_DEVICE = "LFE5U-45F-7BG256I"
SPEED_GRADE = "-7"
DEFAULT_CLOCK_TARGET = 125.0

YOSYS = os.environ.get("YOSYS", "yosys")
NEXTPNR = os.environ.get("NEXTPNR_ECP5", "nextpnr-ecp5")
IVERILOG = os.environ.get("IVERILOG", "iverilog")


class CampaignError(RuntimeError):
    pass


def _run(cmd: list[str], log_path: Path | None = None) -> str:
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(out, encoding="utf-8")
    if proc.returncode != 0:
        tail = "\n".join(out.splitlines()[-25:])
        raise CampaignError(
            f"command failed (rc={proc.returncode}): {' '.join(cmd)}\n{tail}"
        )
    return out


def _require(path: Path, what: str) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise CampaignError(f"expected {what} was not produced: {path}")


_TOOL_CACHE: dict[str, str] = {}


def tool_versions() -> str:
    if _TOOL_CACHE:
        return _TOOL_CACHE["s"]
    def first(cmd: list[str]) -> str:
        try:
            p = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
            line = (p.stdout + p.stderr).strip().splitlines()
            return line[0].strip() if line else "?"
        except FileNotFoundError:
            return "missing"
    parts = {
        "yosys": first([YOSYS, "-V"]),
        "nextpnr": first([NEXTPNR, "--version"]),
        "iverilog": first([IVERILOG, "-V"]),
        "python": f"Python {platform.python_version()}",
        "host": platform.platform(),
    }
    _TOOL_CACHE["s"] = "; ".join(f"{k}={v}" for k, v in parts.items())
    return _TOOL_CACHE["s"]


_CAPTURED_COMMIT: str | None = None


def _repo_commit() -> str:
    if _CAPTURED_COMMIT:
        return _CAPTURED_COMMIT
    try:
        p = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                           capture_output=True, text=True)
        return p.stdout.strip()[:12]
    except Exception:
        return "unknown"


def prepare_sources() -> str:
    """Export the committed ``HEAD`` RTL/synth tree for reproducible benchmarks.

    Benchmarking a pristine export (rather than the live working tree) keeps
    results reproducible and immune to other agents' in-flight edits: the
    recorded commit is exactly the revision that was measured.  The commit is
    captured once here and reused for the whole campaign, so a commit landing
    mid-campaign cannot mix revisions in one report.
    """
    global _CAPTURED_COMMIT
    import io
    import tarfile
    if SRC_ROOT.exists():
        shutil.rmtree(SRC_ROOT)
    SRC_ROOT.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["git", "archive", "--format=tar", "HEAD", "rtl", "synth"],
        cwd=REPO, capture_output=True)
    if proc.returncode != 0:
        raise CampaignError("git archive HEAD failed: "
                            + proc.stderr.decode(errors="replace"))
    with tarfile.open(fileobj=io.BytesIO(proc.stdout)) as tf:
        tf.extractall(SRC_ROOT)
    _CAPTURED_COMMIT = _repo_commit()
    return _CAPTURED_COMMIT


def _src(rel: str) -> Path:
    return SRC_ROOT / rel


def _rtl_files() -> list[str]:
    files: list[str] = []
    for pattern in registry.ALL_RTL:
        files.extend(sorted(str((Path(p).relative_to(REPO)))
                            for p in glob.glob(str(SRC_ROOT / pattern))))
    return files


_ARCH_OPS = {
    "$mul": "multiplications",
    "$add": "additions",
    "$sub": "subtractions",
    "$macc": "multiply_accumulates",
    "$alu": "alu_ops",
    "$lt": "comparators_lt",
    "$le": "comparators_le",
    "$ge": "comparators_ge",
    "$gt": "comparators_gt",
    "$eq": "comparators_eq",
    "$ne": "comparators_ne",
    "$div": "divisions",
}


def parse_arch_stat(text: str) -> dict:
    """Approximate generic-operator census from a Yosys ``stat`` dump.

    Counts are read from the ``<n> cells`` / ``<opcode> <n>`` lines emitted by
    ``stat`` after ``proc; opt`` and before technology mapping.  They are an
    *approximate* architectural fingerprint for a future ASIC comparison, not
    an area estimate.
    """
    import re
    counts: dict[str, int] = {}
    total_cells = 0
    wires = 0
    for m in re.finditer(r"^\s*(?:\\?\$?[A-Za-z0-9_$]+)?\s*(\d+)\s+cells\b", text, re.M):
        total_cells = max(total_cells, int(m.group(1)))
    for m in re.finditer(r"^\s*(\\?\$[a-z0-9_]+)\s+(\d+)\s*$", text, re.M):
        op = m.group(1).lstrip("\\")
        if op in _ARCH_OPS:
            counts[_ARCH_OPS[op]] = counts.get(_ARCH_OPS[op], 0) + int(m.group(2))
    mw = re.search(r"Number of wire bits:\s*(\d+)", text)
    if mw:
        wires = int(mw.group(1))
    counts["total_cells"] = total_cells
    counts["wire_bits"] = wires
    return counts


def _write_yosys_script(path: Path, top: str, extra_sv: list[str],
                        netlist: Path, stat: Path, archstat: Path) -> None:
    rtl = _rtl_files()
    lines = [
        "# AUTO-GENERATED by tools/timing/run.py",
        "read_verilog -lib -specify +/ecp5/cells_sim.v",
        "read_verilog -lib +/ecp5/cells_bb.v",
        "read_verilog -sv " + " ".join(rtl + extra_sv),
        f"hierarchy -check -top {top}",
        "check",
        # Generic (technology-independent) operator census for the future ASIC
        # comparison: taken after proc/opt but before any ECP5 mapping.
        "proc",
        "opt",
        f"tee -o {archstat} stat -top {top}",
        f"synth_ecp5 -top {top} -json {netlist}",
        f"tee -o {stat} stat -top {top}",
        "check",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _nextpnr(out_dir: Path, netlist: Path, lpf: Path, seed: int,
             freq: float = DEFAULT_CLOCK_TARGET) -> np.NextpnrResult:
    report = out_dir / f"nextpnr-s{seed}.json"
    cfg = out_dir / f"nextpnr-s{seed}.config"
    log = out_dir / f"nextpnr-s{seed}.log"
    cmd = [
        NEXTPNR, "--45k", "--package", "CABGA256",
        "--freq", f"{freq:g}",
        "--lpf", str(lpf), "--lpf-allow-unconstrained",
        "--json", str(netlist),
        "--textcfg", str(cfg),
        "--report", str(report),
        "--seed", str(seed),
    ]
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    log.write_text(out, encoding="utf-8")
    # nextpnr exits non-zero when the design misses the timing constraint, but
    # that is a *result*, not a campaign failure.  Only a missing report (or a
    # crash that never finished) is fatal, so there is no silent success.
    if not report.is_file() or report.stat().st_size == 0:
        tail = "\n".join(out.splitlines()[-25:])
        raise CampaignError(
            f"nextpnr produced no report (rc={proc.returncode}); "
            f"place-and-route did not complete:\n{tail}"
        )
    if "Program finished normally" not in out:
        tail = "\n".join(out.splitlines()[-25:])
        raise CampaignError(
            f"nextpnr did not finish normally (rc={proc.returncode}):\n{tail}"
        )
    result = np.parse_report(report.read_text(encoding="utf-8"))
    log_parsed = np.parse_log(log.read_text(encoding="utf-8"))
    problems = np.cross_check(result, log_parsed)
    if problems:
        raise CampaignError(
            f"nextpnr report/log cross-check failed for seed {seed}: "
            + "; ".join(problems)
        )
    return result


def _wrapper_lpf(out_dir: Path) -> Path:
    lpf = out_dir / "timing.lpf"
    lpf.write_text(
        "# AUTO-GENERATED: only the wrapper clock is constrained.\n"
        "BLOCK ASYNCPATHS;\n"
        'FREQUENCY PORT "clk" 125 MHZ;\n',
        encoding="utf-8",
    )
    return lpf


def _fingerprint(block: registry.Bench, mode: str, wrapper_sv: Path | None) -> str:
    import hashlib
    h = hashlib.sha256()
    # The commit is included because all synthesis input comes from the
    # pristine HEAD export: same commit + same wrapper => identical netlist.
    h.update(_repo_commit().encode())
    h.update(block.module.encode())
    h.update(mode.encode())
    if wrapper_sv is not None:
        h.update(wrapper_sv.read_bytes())
    else:
        h.update(_src(block.file).read_bytes())
    return h.hexdigest()[:16]


def benchmark(block: registry.Bench, seeds: list[int], force: bool = False) -> dict:
    out_dir = BUILD / block.module
    out_dir.mkdir(parents=True, exist_ok=True)
    netlist = out_dir / "netlist.json"
    stat = out_dir / "stat.txt"

    if block.direct:
        top = block.module
        lpf = _src(block.lpf or "synth/dcf77_hat_top.lpf")
        if not lpf.is_file():
            raise CampaignError(f"direct-mode LPF not found: {lpf}")
        mode = "direct"
        wrapper_sv = None
    else:
        src = _src(block.file)
        if not src.is_file():
            raise CampaignError(f"source not found: {src}")
        wrapper_sv = out_dir / "wrapper.sv"
        # Regenerate every time so the wrapper always matches the current RTL ports.
        text, _ports = wrappergen.wrapper_for_source(
            block.module, src.read_text(encoding="utf-8"), block.clock, block.file,
            block.param_dict)
        wrapper_sv.write_text(text, encoding="utf-8")
        top = f"{block.module}__timing"
        lpf = _wrapper_lpf(out_dir)
        mode = "wrapper"

    fp = _fingerprint(block, mode, wrapper_sv)
    cached_path = RAW / f"{block.module}.json"
    if not force and cached_path.is_file():
        cached = json.loads(cached_path.read_text(encoding="utf-8"))
        if cached.get("fingerprint") == fp and cached.get("tool_versions") == tool_versions():
            print(f"[cache] {block.module}: reusing {cached_path.name}", flush=True)
            return cached

    script = out_dir / "synth.ys"
    archstat = out_dir / "arch.txt"
    extra = [str(wrapper_sv.relative_to(REPO))] if mode == "wrapper" else []
    _write_yosys_script(script, top, extra, netlist, stat, archstat)
    _run([YOSYS, "-s", str(script.relative_to(REPO))], log_path=out_dir / "yosys.log")
    _require(netlist, "yosys netlist json")
    _require(stat, "yosys stat")
    arch = parse_arch_stat(archstat.read_text(encoding="utf-8")) if archstat.is_file() else {}

    per_seed = []
    for seed in seeds:
        try:
            res = _nextpnr(out_dir, netlist, lpf, seed)
        except ValueError as exc:
            # e.g. an empty/degenerate design has no 'fmax' section: this is a
            # real failure, never a silent success.
            raise CampaignError(f"could not parse nextpnr report for seed {seed}: {exc}")
        per_seed.append((seed, res))
    primary_seed, primary = per_seed[0]

    record = {
        "module": block.module,
        "file": block.file,
        "kind": block.kind,
        "mode": mode,
        "clock": block.clock,
        "clock_target_mhz": primary.constraint_mhz or DEFAULT_CLOCK_TARGET,
        "latency": block.latency,
        "throughput": block.throughput,
        "config": block.config_label,
        "notes": block.notes,
        "commit": _repo_commit(),
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "target_device": TARGET_DEVICE,
        "speed_grade": SPEED_GRADE,
        "seed": primary_seed,
        "fmax_mhz": round(primary.fmax_mhz, 3),
        "worst_slack_ns": round(primary.worst_slack_ns, 3),
        "timing_met": primary.worst_slack_ns >= 0.0,
        "lut4": primary.lut4,
        "ff": primary.ff,
        "ebr18": primary.ebr18,
        "mult18x18d": primary.mult18x18d,
        "pll": primary.pll,
        "ramw": primary.ramw,
        "critical_path_summary": primary.critical_path_summary,
        "critical_paths": [
            {"source": p.source, "dest": p.dest, "total_ns": round(p.total_ns, 3),
             "logic_ns": round(p.logic_ns, 3), "route_ns": round(p.route_ns, 3),
             "segments": p.segments, "types": p.types}
            for p in primary.critical_paths
        ],
        "multi_seed": [
            {"seed": s, "fmax_mhz": round(r.fmax_mhz, 3)} for s, r in per_seed
        ],
        "arch": arch,
        "fingerprint": fp,
        "tool_versions": tool_versions(),
    }
    return record


def _save(record: dict) -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    (RAW / f"{record['module']}.json").write_text(
        json.dumps(record, indent=1), encoding="utf-8")


def _campaign(block_names: list[str], seeds: list[int]) -> list[dict]:
    commit = prepare_sources()
    print(f"[src] benchmarking pristine HEAD export {commit} "
          f"(build/timing/src)", flush=True)
    records = []
    failures = []
    for name in block_names:
        block = registry.get_block(name)
        if not (block.isolated or block.direct):
            print(f"[skip] {name}: documented exception ({block.notes})", flush=True)
            continue
        print(f"[bench] {name} ({block.kind}) ...", flush=True)
        try:
            rec = benchmark(block, seeds)
        except CampaignError as exc:
            failures.append((name, str(exc)))
            print(f"[FAIL] {name}: {exc}", flush=True)
            continue
        _save(rec)
        records.append(rec)
        print(f"[ok]   {name}: Fmax {rec['fmax_mhz']:.2f} MHz  "
              f"LUT {rec['lut4']}  FF {rec['ff']}  MULT {rec['mult18x18d']}  "
              f"EBR {rec['ebr18']}  slack {rec['worst_slack_ns']:.2f} ns", flush=True)
    # Always regenerate the reports from the raw records collected so far, so a
    # single failing block does not discard the campaign's good measurements.
    from . import report as reportmod
    reportmod.generate()
    if failures:
        print("\n=== FAILURES ===", file=sys.stderr)
        for name, msg in failures:
            print(f"  {name}: {msg}", file=sys.stderr)
        raise CampaignError(f"{len(failures)} benchmark(s) failed")
    return records


def _seeds_from(args) -> list[int]:
    if args.seeds:
        return [int(s) for s in args.seeds.split(",") if s.strip()]
    return [1]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="BEA-37 block timing characterisation")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("block", "subsystem"):
        p = sub.add_parser(name)
        p.add_argument("--name", required=True)
        p.add_argument("--seeds", default=None)
    for name in ("all-blocks", "all-subsystems", "profile"):
        p = sub.add_parser(name)
        p.add_argument("--seeds", default=None)
        p.add_argument("--only", default=None, help="comma-separated subset of module names")
    args = ap.parse_args(argv)

    # Imported here so a parsing-only test does not need report machinery.
    from . import report as reportmod

    if args.cmd == "block":
        registry.get_block(args.name)  # validate (exits clearly if unknown)
        recs = _campaign([args.name], _seeds_from(args))
    elif args.cmd == "subsystem":
        if args.name not in registry.SUBSYSTEMS:
            raise SystemExit(f"unknown subsystem {args.name!r}; known: "
                             f"{', '.join(sorted(registry.SUBSYSTEMS))}")
        recs = _campaign([registry.SUBSYSTEMS[args.name]], _seeds_from(args))
    elif args.cmd == "all-blocks":
        names = [b.module for b in registry.isolated_blocks()]
        if args.only:
            wanted = set(args.only.split(","))
            names = [n for n in names if n in wanted]
        recs = _campaign(names, _seeds_from(args))
    elif args.cmd == "all-subsystems":
        names = sorted(set(registry.SUBSYSTEMS.values()))
        recs = _campaign(names, _seeds_from(args))
    elif args.cmd == "profile":
        names = sorted({b.module for b in registry.isolated_blocks()}
                       | set(registry.SUBSYSTEMS.values())
                       | {"dcf77_hat_top"})
        recs = _campaign(names, _seeds_from(args))
    else:  # pragma: no cover
        raise SystemExit(f"unknown command {args.cmd}")

    reportmod.generate()
    print(f"\n== wrote {len(recs)} benchmark record(s); reports regenerated ==")
    return 0


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except CampaignError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
