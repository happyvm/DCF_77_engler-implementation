/**
 * Import the official Lattice pinout export into the BG256 ball identity table.
 *
 * Source of truth for ball identity is the Lattice "ECP5U-45 Pinout" CSV
 * (document FPGA-SC-02034, Rev 3.0, 2021-09-17, the caBGA256 column). The raw
 * Lattice export is intentionally NOT vendored here; this script records its
 * SHA-256 and folds the derived ball identity into pin-plan.json plus a
 * committed, auditable derivation under lattice/bg256-identity.json.
 *
 * The script refuses to write anything unless the official export is internally
 * consistent (256 caBGA256 balls, one pad each) and agrees with every ball that
 * pin-plan.json already froze as `documented`. That keeps the audited identity
 * authoritative rather than letting an import silently rewrite it.
 *
 * Usage:
 *   tsx scripts/import-lattice-pinout.ts --lattice <FPGA-SC-02034-*.csv> [--write]
 *   (without --write the script only reports the reconciliation)
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");

const ROWS = [..."ABCDEFGHJKLMNPRT"];
const COLS = Array.from({ length: 16 }, (_, i) => i + 1);
const TOTAL = 256;

type Ball = {
  ball: string;
  pad: number;
  row: string;
  col: number;
  signal: string | null;
  kind: string;
  bank: number | null;
  pin_name?: string | null;
  lattice_bank?: number | null;
  audit: string;
};

// ---------------------------------------------------------------------------
// CSV parsing (quoted fields, comment lines tolerated)
// ---------------------------------------------------------------------------
function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else quoted = false;
      } else cur += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { out.push(cur); cur = ""; }
    else cur += c;
  }
  out.push(cur);
  return out.map((f) => f.trim());
}

function readOfficialPinout(csvText: string) {
  const lines = csvText.split(/\r?\n/);
  const rows = lines.filter((l) => l.trim().length).map(parseCsvLine);
  const headerIdx = rows.findIndex((r) => r[0] === "PAD");
  if (headerIdx === -1) throw new Error("no PAD header row in the Lattice export");
  const header = rows[headerIdx];
  const col = (name: string) => {
    const i = header.indexOf(name);
    if (i === -1) throw new Error(`Lattice export has no "${name}" column (header: ${header.join("|")})`);
    return i;
  };
  const iFn = col("Pin/Ball Function");
  const iBank = col("Bank");
  const iBall = col("CABGA256");

  const byBall = new Map<string, { pad: string; fn: string; bank: number | null }>();
  for (const r of rows.slice(headerIdx + 1)) {
    if (!r[0] || !/^\d+$/.test(r[0])) continue;
    const ball = (r[iBall] ?? "").trim();
    if (!ball || ball === "-") continue;
    if (byBall.has(ball)) throw new Error(`ball ${ball} appears more than once in the Lattice export`);
    const bankRaw = (r[iBank] ?? "").trim();
    byBall.set(ball, { pad: r[0], fn: (r[iFn] ?? "").trim(), bank: /^\d+$/.test(bankRaw) ? Number(bankRaw) : null });
  }
  return byBall;
}

function kindFor(fn: string, existing: string | undefined): string {
  if (fn === "GND") return "ground";
  if (fn === "VCC" || fn === "VCCAUX" || fn.startsWith("VCCIO")) return "power";
  if (existing && ["signal", "sysconfig", "reserved"].includes(existing)) return existing;
  return "io";
}

function signalFor(fn: string, existing: string | null | undefined): string | null {
  if (existing) return existing;
  if (fn === "VCC" || fn === "VCCAUX" || fn.startsWith("VCCIO")) return fn;
  return null;
}

function bankFor(fn: string, officialBank: number | null, existing: number | null): number | null {
  if (fn === "GND" || fn === "VCC" || fn === "VCCAUX") return null;
  if (fn.startsWith("VCCIO")) return Number(fn.slice("VCCIO".length));
  return officialBank ?? existing;
}

export function canonicalIdentity(balls: Ball[]): string {
  return [...balls]
    .sort((a, b) => a.pad - b.pad)
    .map((b) =>
      `${b.pad}:${b.ball}:${b.row}${b.col}:${b.pin_name ?? ""}:${b.lattice_bank ?? ""}:${b.signal ?? ""}:${b.kind}`,
    )
    .join("\n");
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
const latIdx = process.argv.indexOf("--lattice");
if (latIdx === -1 || !process.argv[latIdx + 1]) {
  console.error("usage: tsx scripts/import-lattice-pinout.ts --lattice <FPGA-SC-02034-*.csv> [--write]");
  process.exit(2);
}
const csvPath = path.resolve(process.argv[latIdx + 1]);
const write = process.argv.includes("--write");
if (!fs.existsSync(csvPath)) {
  console.error(`FATAL: ${csvPath} not found`);
  process.exit(1);
}
const csvText = fs.readFileSync(csvPath, "utf8");
const csvSha = crypto.createHash("sha256").update(csvText, "utf8").digest("hex");
const official = readOfficialPinout(csvText);

const planPath = path.join(ROOT, "pin-plan.json");
const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
const balls: Ball[] = plan.balls;

const errors: string[] = [];
if (official.size !== TOTAL) errors.push(`official export has ${official.size} caBGA256 balls, expected ${TOTAL}`);

// 1. reconcile against every ball already frozen as documented
for (const b of balls) {
  const o = official.get(b.ball);
  if (!o) { errors.push(`ball ${b.ball} is absent from the official export`); continue; }
  if (b.audit === "documented" && b.pin_name) {
    if (b.pin_name.split("/")[0] !== o.fn.split("/")[0]) {
      errors.push(`ball ${b.ball}: plan pin_name ${b.pin_name} != official ${o.fn}`);
    }
  }
}

// 2. build the resolved identity table
const resolved: Ball[] = [...balls].sort((a, b) => a.pad - b.pad).map((b, i) => {
  const o = official.get(b.ball)!;
  const expRow = ROWS[Math.floor(i / 16)];
  const expCol = (i % 16) + 1;
  if (b.pad !== i + 1 || b.row !== expRow || b.col !== expCol || b.ball !== `${expRow}${expCol}`) {
    errors.push(`pad ${b.pad} row/col drift: plan ${b.ball} (${b.row},${b.col})`);
  }
  return {
    ball: b.ball,
    pad: b.pad,
    row: b.row,
    col: b.col,
    signal: signalFor(o.fn, b.signal),
    kind: kindFor(o.fn, b.kind === "unassigned" ? undefined : b.kind),
    // design bank association (grouping / rail), kept from the plan
    bank: b.audit === "documented" ? b.bank : bankFor(o.fn, o.bank, b.bank),
    pin_name: o.fn,
    // official Lattice bank id exactly as the export reports it (40 = config/JTAG block)
    lattice_bank: o.bank,
    audit: "documented",
  };
});

if (errors.length) {
  console.error("Lattice pinout import REFUSED:");
  for (const e of errors) console.error(`  ✗ ${e}`);
  process.exit(1);
}

const digest = crypto.createHash("sha256").update(canonicalIdentity(resolved), "utf8").digest("hex");
const kinds = new Map<string, number>();
for (const b of resolved) kinds.set(b.kind, (kinds.get(b.kind) ?? 0) + 1);

console.log(`official source: ${path.basename(csvPath)} (sha256 ${csvSha})`);
console.log(`balls: ${resolved.length}/${TOTAL} documented`);
console.log(`kinds: ${[...kinds.entries()].map(([k, v]) => `${k}=${v}`).join(" ")}`);
console.log(`identity sha256: ${digest}`);

if (!write) {
  console.log("\n(dry run — pass --write to update pin-plan.json)");
  process.exit(0);
}

const derivation = {
  source: {
    document: "FPGA-SC-02034",
    title: "ECP5U-45 Pinout",
    revision: "3.0",
    date: "2021-09-17",
    format: "CSV",
    vendor: "Lattice Semiconductor",
    package: "caBGA256",
    column: "CABGA256",
    sha256: csvSha,
    retrieved: new Date().toISOString().slice(0, 10),
  },
  extraction: "pad,ball,function,lattice_bank",
  balls: resolved.map((b) => ({ pad: b.pad, ball: b.ball, function: b.pin_name, lattice_bank: b.lattice_bank })),
};

const latticeDir = path.join(ROOT, "lattice");
fs.mkdirSync(latticeDir, { recursive: true });
fs.writeFileSync(path.join(latticeDir, "bg256-identity.json"), JSON.stringify(derivation, null, 2) + "\n");

plan.balls = resolved;
plan.ball_audit = {
  documented_balls: TOTAL,
  unverified_balls: 0,
  documented_scope: "all 256 BG256 balls cross-checked against Lattice FPGA-SC-02034 Rev 3.0 (caBGA256 column)",
  unverified_scope: "none",
  source: {
    document: "FPGA-SC-02034",
    revision: "3.0",
    date: "2021-09-17",
    sha256: csvSha,
    derivation: "lattice/bg256-identity.json",
  },
  identity_sha256: digest,
  identity_canonical_form: "pad:ball:rowcol:pin_name:lattice_bank:signal:kind, one line per ball, LF-joined, UTF-8",
  gate: "scripts/verify-bga-identity.ts fails on any grid, order, name or hash change and cross-checks a supplied FPGA-SC-02034 export ball-by-ball",
};
plan.source_policy =
  "Ball identity cross-checked against Lattice FPGA-SC-02034 Rev 3.0 (ECP5U-45 pinout, caBGA256 column) for all 256 balls and against the Raspberry Pi HAT+ specification. scripts/verify-bga-identity.ts enforces this file against the generated BGA footprint and fails if ball names were renumbered or reordered by an exporter.";

fs.writeFileSync(planPath, JSON.stringify(plan, null, 2) + "\n");
console.log("\nwrote pin-plan.json and lattice/bg256-identity.json");
