/**
 * Pre-routing ERC/DRC gate.
 *
 * Runs the four `tsci check` passes the schematic freeze requires and turns them
 * into one exit code:
 *   - source   : ERC, must be 0 errors / 0 warnings
 *   - netlist  : every net resolves
 *   - shorts   : no unintended copper shorts
 *   - placement: 0 errors; the only allowance is the pair of informational
 *                `pcb_connector_not_in_accessible_orientation_warning` entries
 *                for the mechanically fixed HAT+ 40-pin header (J1) and the
 *                edge-reachable JTAG header (J2). `tsci check placement` exits
 *                non-zero on any warning, so the allowance is checked explicitly
 *                here instead of being masked with `|| true`.
 *
 * Usage: npm run check:erc   (needs `bun` on PATH for the tsci shebang)
 */
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const ENTRY = "src/index.tsx";
const TSCI = path.join(ROOT, "node_modules", ".bin", "tsci");

/** Connector warnings that are fixed by the HAT+/JTAG mechanical spec, not defects. */
const ALLOWED_PLACEMENT_WARNINGS = [
  "pcb_connector_not_in_accessible_orientation_warning",
];

type Result = { name: string; rc: number; out: string };

function run(name: string, args: string[]): Result {
  try {
    const out = execFileSync(TSCI, args, { cwd: ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    return { name, rc: 0, out };
  } catch (err: any) {
    return { name, rc: typeof err.status === "number" ? err.status : 1, out: `${err.stdout ?? ""}${err.stderr ?? ""}` };
  }
}

const failures: string[] = [];
const clean = (r: Result) => {
  const errors = Number(/Errors:\s*(\d+)/.exec(r.out)?.[1] ?? 0);
  const warnings = Number(/Warnings:\s*(\d+)/.exec(r.out)?.[1] ?? 0);
  if (r.rc !== 0) failures.push(`${r.name}: exited ${r.rc}`);
  if (errors > 0) failures.push(`${r.name}: ${errors} error(s)`);
  if (warnings > 0) failures.push(`${r.name}: ${warnings} unexpected warning(s)`);
  console.log(`  · ${r.name}: exit ${r.rc}, ${errors} errors, ${warnings} warnings`);
};

for (const name of ["source", "netlist", "shorts"]) {
  clean(run(name, ["check", name, ENTRY]));
}

const placement = run("placement", ["check", "placement", ENTRY]);
const pErrors = Number(/Errors:\s*(\d+)/.exec(placement.out)?.[1] ?? 0);
const pWarnings = Number(/Warnings:\s*(\d+)/.exec(placement.out)?.[1] ?? 0);
// Only the block after the summary line carries warning entries, one per
// `- <warning_type>:` line; the following lines are indented detail text.
const warningSection = placement.out.slice(placement.out.lastIndexOf("Warnings:"));
const warningTypes = [...warningSection.matchAll(/^-\s+([a-z0-9_]+_warning):/gim)].map((m) => m[1]);
const unexpected = warningTypes.filter((t) => !ALLOWED_PLACEMENT_WARNINGS.includes(t));
if (pErrors > 0) failures.push(`placement: ${pErrors} error(s)`);
if (warningTypes.length !== pWarnings) {
  failures.push(`placement: reported ${pWarnings} warning(s) but parsed ${warningTypes.length} entries`);
}
for (const t of unexpected) failures.push(`placement: unexpected warning type ${t}`);
console.log(
  `  · placement: exit ${placement.rc}, ${pErrors} errors, ` +
    `${pWarnings} warning(s) (${unexpected.length} unexpected)`,
);

if (failures.length) {
  console.error(`\nERC/DRC gate FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log("\nERC/DRC gate PASSED — source/netlist/shorts clean, placement 0 errors");
