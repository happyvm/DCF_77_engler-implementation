/**
 * IC pin-identity verification — SAFETY CRITICAL.
 *
 * The ECP5 ball identity is frozen by pin-plan.json and gated by
 * scripts/verify-bga-identity.ts. This script is the equivalent gate for the
 * non-FPGA ICs: hardware/tscircuit/ic-pinouts.json holds the audited
 * pad-number-to-pin-name map, and the TSX must consume it through
 * `pinLabelsOf("<ref>")` instead of inlining an invented label map.
 *
 * An invented pin label is not a cosmetic problem: it moves a net to the wrong
 * physical pad, which on a mixed-signal board is a fabrication-blocking defect
 * (see docs/14-hardware-cad-tscircuit.md -> hard rules).
 *
 * Checks (all fatal):
 *   1. the JSON parses and carries the expected schema tag;
 *   2. every audited part declares source.document, source.url, source.retrieved
 *      and source.retrieved_artifact_sha256 (no un-sourced pin map);
 *   3. every part's pins form a contiguous 1..N pad sequence with no gap;
 *   4. every pin name is non-empty and unique inside its package (tscircuit
 *      resolves `connections` by label, so a duplicate silently merges pads);
 *   5. status.audited matches the populated parts 1:1 and never overlaps
 *      status.pending;
 *   6. each audited part is actually consumed via `pinLabelsOf("<ref>")`
 *      somewhere under src/.
 *
 * Reported but not fatal by default:
 *   7. the parts listed in status.pending still carry un-cross-checked pin maps.
 *      `--release` turns that into a hard failure, exactly like
 *      `npm run check:bga:release` does for an incomplete ball audit.
 *
 * Usage:
 *   tsx scripts/verify-ic-pinouts.ts
 *   tsx scripts/verify-ic-pinouts.ts --release
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const RELEASE = process.argv.includes("--release");

const PLAN_PATH = path.join(ROOT, "ic-pinouts.json");
const SRC = path.join(ROOT, "src");

type Part = {
  ref: string;
  opn: string;
  device: string;
  package: string;
  pins: Record<string, string>;
  source: {
    document?: string;
    url?: string;
    retrieved?: string;
    retrieved_artifact_sha256?: string;
  };
};

type Plan = {
  schema: string;
  status: { audited: string[]; pending: string[]; pending_scope?: string };
  parts: Record<string, Part>;
};

const failures: string[] = [];
const fail = (msg: string) => failures.push(msg);
const ok = (msg: string) => console.log(`  · ${msg}`);

if (!fs.existsSync(PLAN_PATH)) {
  console.error(`FATAL: ${PLAN_PATH} not found`);
  process.exit(1);
}

let plan: Plan;
try {
  plan = JSON.parse(fs.readFileSync(PLAN_PATH, "utf8")) as Plan;
} catch (e) {
  console.error(`FATAL: ${PLAN_PATH} is not valid JSON: ${(e as Error).message}`);
  process.exit(1);
}

if (plan.schema !== "dcf77-hardware/ic-pinouts@1") {
  fail(`unexpected schema tag "${plan.schema}"`);
}

const audited = Object.keys(plan.parts ?? {});
const declared = plan.status?.audited ?? [];

// --- 5. status bookkeeping -------------------------------------------------
const pending = plan.status?.pending ?? [];
for (const ref of declared) {
  if (!plan.parts[ref]) fail(`status.audited lists "${ref}" but parts."${ref}" is missing`);
}
for (const ref of audited) {
  if (!declared.includes(ref)) fail(`parts."${ref}" is populated but missing from status.audited`);
}
for (const ref of pending) {
  if (declared.includes(ref)) fail(`"${ref}" is listed as both audited and pending`);
}

// --- 1..4. per-part structure ---------------------------------------------
for (const ref of audited) {
  const p = plan.parts[ref];
  for (const field of ["document", "url", "retrieved", "retrieved_artifact_sha256"] as const) {
    if (!p.source?.[field]) fail(`${ref}: source.${field} is missing — an un-sourced pin map cannot be audited`);
  }

  const keys = Object.keys(p.pins ?? {});
  const n = keys.length;
  if (n === 0) {
    fail(`${ref}: no pins declared`);
    continue;
  }
  for (let i = 1; i <= n; i++) {
    if (!(`pin${i}` in p.pins)) {
      fail(`${ref}: pad sequence gap at pin${i} (declared ${n} pads)`);
      break;
    }
  }
  const names = Object.values(p.pins);
  const dup = names.filter((v, i) => names.indexOf(v) !== i);
  if (dup.length) fail(`${ref}: duplicate pin names ${[...new Set(dup)].join(", ")} — connections resolve by label`);
  for (const [k, v] of Object.entries(p.pins)) {
    if (!v || !v.trim()) fail(`${ref}: ${k} has an empty pin name`);
  }
  ok(`${ref} (${p.opn ?? "?"}): ${n} pads, ${p.package ?? "?"}, source ${p.source?.document ?? "?"}`);
}

// --- 6. the audited map must actually be consumed --------------------------
function walk(dir: string, out: string[] = []): string[] {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (/\.(tsx?|json)$/.test(e.name)) out.push(full);
  }
  return out;
}

const sources = fs.existsSync(SRC) ? walk(SRC) : [];
const sourceText = sources.map((f) => ({ f, t: fs.readFileSync(f, "utf8") }));
for (const ref of audited) {
  const needle = `pinLabelsOf("${ref}")`;
  const hit = sourceText.find((s) => s.t.includes(needle));
  if (!hit) fail(`${ref}: no source under src/ uses ${needle} — the audited map is not wired in`);
  else ok(`${ref}: consumed by ${path.relative(ROOT, hit.f)}`);
}

// --- 7. pending audit ------------------------------------------------------
if (pending.length) {
  const msg = `${pending.length} part(s) still carry an un-audited pad identity: ${pending.join(", ")}`;
  console.log(`  ! ${msg}`);
  if (plan.status?.pending_scope) console.log(`    ${plan.status.pending_scope}`);
  if (RELEASE) fail(`${msg} — release build refused`);
}

if (failures.length) {
  console.error("\nIC pin-identity verification FAILED");
  for (const f of failures) console.error(`  x ${f}`);
  process.exit(1);
}

console.log(`\nIC pin-identity verification PASSED — ${audited.length} audited part(s), ${pending.length} pending`);
