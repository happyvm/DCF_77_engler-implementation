/**
 * BGA256 ball-identity verification — SAFETY CRITICAL.
 *
 * docs/14-hardware-cad-tscircuit.md: "Do not release fabrication output if ball
 * names were renumbered or reordered by an exporter."
 *
 * This script is the automated gate. It fails (exit 1) when any of the following
 * drift from hardware/tscircuit/pin-plan.json:
 *
 *   1. the BG256 ball grid (rows A..T without I/O/Q/S, columns 1..16);
 *   2. the pad numbering order (row-major from the top-left corner);
 *   3. the geometric position of every pad of the generated BGA footprint;
 *   4. the footprint pitch (must stay 0.8 mm per the Lattice BG256 package);
 *   5. the SHA-256 fingerprint of the audited ball identity table;
 *   6. the coverage of the identity table (must reach 256 documented balls).
 *
 * The ECP5 chip wrapper (src/parts/ecp5_bg256.tsx) derives its pin labels from
 * this same file, so a failure here means the exported netlist/PCB no longer
 * matches the audited ball identity.
 *
 * Usage:
 *   tsx scripts/verify-bga-identity.ts
 *   tsx scripts/verify-bga-identity.ts --lattice <FPGA-SC-02034.csv>
 *   tsx scripts/verify-bga-identity.ts --allow-incomplete-audit
 *
 * --lattice cross-checks every ball against the official Lattice pinout export
 * (the CSV cannot be redistributed here; it requires an authenticated Lattice
 * download). Without it, only the 69 balls named by docs/23, docs/27 and this
 * plan are treated as documented and the remaining 187 grid-derived balls keep
 * the audit incomplete, which blocks fabrication release.
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const planArgIdx = process.argv.indexOf("--plan");
const PLAN_PATH =
  planArgIdx !== -1 && process.argv[planArgIdx + 1]
    ? path.resolve(process.argv[planArgIdx + 1])
    : path.join(ROOT, "pin-plan.json");

const ROWS = [..."ABCDEFGHJKLMNPRT"];
const COLS = Array.from({ length: 16 }, (_, i) => i + 1);
const PITCH_MM = 0.8;
const EXPECTED_TOTAL = 256;

type Ball = {
  ball: string;
  pad: number;
  row: string;
  col: number;
  signal: string | null;
  kind: string;
  bank: number | null;
  audit: string;
};

type Plan = {
  device: string;
  package: string;
  ball_grid: { rows: string[]; cols: number[]; count: number };
  ball_audit: { identity_sha256: string; documented_balls: number; unverified_balls: number };
  balls: Ball[];
};

const failures: string[] = [];
const notes: string[] = [];
function fail(msg: string) {
  failures.push(msg);
}
function check(cond: boolean, msg: string) {
  if (!cond) fail(msg);
  return cond;
}

// --------------------------------------------------------------------------
// 1. load + structural checks
// --------------------------------------------------------------------------
if (!fs.existsSync(PLAN_PATH)) {
  console.error(`FATAL: ${PLAN_PATH} not found`);
  process.exit(1);
}
const plan = JSON.parse(fs.readFileSync(PLAN_PATH, "utf8")) as Plan;

check(plan.device === "LFE5U-45F-7BG256I", `device is "${plan.device}", expected LFE5U-45F-7BG256I`);
check(plan.package === "BG256", `package is "${plan.package}", expected BG256`);
check(Array.isArray(plan.balls), "pin-plan.json has no balls[] table");

const balls = plan.balls ?? [];
check(balls.length === EXPECTED_TOTAL, `balls[] has ${balls.length} entries, expected ${EXPECTED_TOTAL}`);

// grid completeness: every (row, col) once
const seen = new Set<string>();
const seenPad = new Set<number>();
for (const b of balls) {
  if (!/^[A-Z][0-9]{1,2}$/.test(b.ball)) fail(`malformed ball name "${b.ball}"`);
  if (seen.has(b.ball)) fail(`duplicate ball name "${b.ball}"`);
  seen.add(b.ball);
  if (seenPad.has(b.pad)) fail(`duplicate pad number ${b.pad}`);
  seenPad.add(b.pad);
  if (!ROWS.includes(b.ball[0])) fail(`ball "${b.ball}" uses a row letter outside A..T (I/O/Q/S are not valid BG256 rows)`);
  const col = Number(b.ball.slice(1));
  if (col < 1 || col > 16) fail(`ball "${b.ball}" has a column outside 1..16`);
}
for (const r of ROWS) for (const c of COLS) {
  if (!seen.has(`${r}${c}`)) fail(`missing ball ${r}${c} — grid is not a complete 16x16 BG256 array`);
}

// --------------------------------------------------------------------------
// 2. pad numbering order (row-major, top-left origin)
// --------------------------------------------------------------------------
const ordered = [...balls].sort((a, b) => a.pad - b.pad);
ordered.forEach((b, i) => {
  const expectedPad = i + 1;
  if (b.pad !== expectedPad) fail(`pad numbering gap at index ${i}: pad=${b.pad}`);
  const expRow = ROWS[Math.floor(i / 16)];
  const expCol = (i % 16) + 1;
  if (b.ball !== `${expRow}${expCol}`) {
    fail(`pad ${expectedPad} is "${b.ball}" but row-major top-left order requires "${expRow}${expCol}"`);
  }
  if (b.row !== expRow || b.col !== expCol) {
    fail(`ball "${b.ball}" has row/col (${b.row},${b.col}) inconsistent with its name`);
  }
});

// --------------------------------------------------------------------------
// 3. documented coverage
// --------------------------------------------------------------------------
const documented = balls.filter((b) => b.audit === "documented");
const unverified = balls.filter((b) => b.audit !== "documented");
notes.push(`documented balls: ${documented.length}/${EXPECTED_TOTAL}`);
notes.push(`unverified balls: ${unverified.length}/${EXPECTED_TOTAL}`);

const requiredSignals = [
  "CLK_25M", "ADC_SCK", "ADC_SDO", "ADC_CONV", "PGA_SCK", "PGA_MOSI", "PGA_CS_N",
  "PPS_REF", "LCD_SCL", "LCD_SDA", "LCD_RST_N", "LCD_BL_EN",
  "HAT_SPI_MOSI", "HAT_SPI_MISO", "HAT_SPI_SCLK", "HAT_SPI_CS_N", "HAT_IRQ",
  "HAT_RESET_N", "HAT_PPS", "HAT_UART_TX", "HAT_UART_RX",
];
const bySignal = new Map<string, Ball>();
for (const b of balls) if (b.signal) bySignal.set(b.signal, b);
for (const s of requiredSignals) check(bySignal.has(s), `documented signal "${s}" is missing from pin-plan.json`);
for (const rail of ["VCC", "VCCAUX", "VCCIO0", "VCCIO1", "VCCIO2", "VCCIO3", "VCCIO6", "VCCIO7", "VCCIO8"]) {
  check(bySignal.has(rail), `power ball group "${rail}" is missing from pin-plan.json`);
}
// spot-check the frozen ball identity of critical signals
const frozen: Record<string, string> = {
  CLK_25M: "C9", ADC_SCK: "J16", ADC_SDO: "J15", ADC_CONV: "K16",
  HAT_SPI_MOSI: "A10", HAT_SPI_MISO: "D11", HAT_UART_TX: "A13", HAT_UART_RX: "A14",
  PPS_REF: "R12", LCD_SCL: "M13", LCD_SDA: "N14",
};
for (const [sig, ball] of Object.entries(frozen)) {
  const got = bySignal.get(sig)?.ball;
  check(got === ball, `${sig} is on ball ${got}, frozen identity requires ${ball}`);
}

// --------------------------------------------------------------------------
// 4. SHA-256 fingerprint of the identity table
// --------------------------------------------------------------------------
const canonical = ordered
  .map((b) => `${b.pad}:${b.ball}:${b.row}${b.col}:${b.signal ?? ""}:${b.kind}`)
  .join("\n");
const digest = crypto.createHash("sha256").update(canonical, "utf8").digest("hex");
const expected = plan.ball_audit?.identity_sha256;
check(digest === expected, `ball identity SHA-256 drifted: computed ${digest}, pin-plan declares ${expected}`);
if (digest === expected) notes.push(`identity sha256 ok: ${digest}`);

// --------------------------------------------------------------------------
// 5. generated BGA footprint geometry (exporter renumbering gate)
// --------------------------------------------------------------------------
const { footprinter } = await import("@tscircuit/footprinter");
const builder = (footprinter as any)().bga(EXPECTED_TOTAL).grid("16x16");
const soup = builder.soup() as Array<Record<string, any>>;
const pads = soup.filter((e) => e.type === "pcb_smtpad");
check(pads.length === EXPECTED_TOTAL, `generated footprint exposes ${pads.length} pads, expected ${EXPECTED_TOTAL}`);

if (pads.length === EXPECTED_TOTAL) {
  const xs = pads.map((p) => p.x as number);
  const ys = pads.map((p) => p.y as number);
  const minX = Math.min(...xs);
  const minY = Math.min(...ys);
  const pitchX = Math.abs(pads[1].x - pads[0].x);
  const pitchY = Math.abs(pads[16].y - pads[0].y);
  check(Math.abs(pitchX - PITCH_MM) < 1e-6, `footprint x pitch is ${pitchX}mm, BG256 requires ${PITCH_MM}mm`);
  check(Math.abs(pitchY - PITCH_MM) < 1e-6, `footprint y pitch is ${pitchY}mm, BG256 requires ${PITCH_MM}mm`);

  for (const pad of pads) {
    const padNum = Number((pad.port_hints ?? [])[0]);
    if (!Number.isFinite(padNum)) {
      fail(`generated pad at (${pad.x},${pad.y}) has no numeric port hint — exporter renumbering risk`);
      continue;
    }
    const rowIdx = Math.round((pad.y - minY) / PITCH_MM);
    const colIdx = Math.round((pad.x - minX) / PITCH_MM);
    const geoBall = `${ROWS[rowIdx] ?? "?"}${colIdx + 1}`;
    const planBall = ordered[padNum - 1]?.ball;
    if (geoBall !== planBall) {
      fail(
        `pad${padNum} sits at grid ${geoBall} in the generated footprint but pin-plan.json ` +
        `places ${planBall} there — ball order/renumbering detected`,
      );
    }
  }
  if (!failures.length) notes.push("generated BGA footprint geometry matches pin-plan.json pad order");
}

// --------------------------------------------------------------------------
// 6. optional cross-check against the official Lattice pinout export
// --------------------------------------------------------------------------
const latticeArg = process.argv.indexOf("--lattice");
const allowIncomplete = process.argv.includes("--allow-incomplete-audit");
if (latticeArg !== -1) {
  const csvPath = process.argv[latticeArg + 1];
  if (!csvPath || !fs.existsSync(csvPath)) {
    fail(`--lattice given but file not readable: ${csvPath}`);
  } else {
    const text = fs.readFileSync(csvPath, "utf8");
    const lines = text.split(/\r?\n/).filter((l) => l.trim().length);
    // Lattice pinout CSVs are "Package,Ball,Signal,..." shaped; accept any header
    // order and key off the Ball column, comparing against our ball set.
    const header = lines[0].split(",").map((h) => h.trim().toLowerCase());
    const ballIdx = header.findIndex((h) => h === "ball" || h === "ball name" || h === "ballname");
    if (ballIdx === -1) {
      fail(`--lattice CSV has no "ball" column (header: ${lines[0]})`);
    } else {
      const official = new Set(lines.slice(1).map((l) => l.split(",")[ballIdx]?.trim()).filter(Boolean));
      for (const b of balls) {
        if (!official.has(b.ball)) fail(`ball ${b.ball} is not present in the supplied Lattice pinout export`);
      }
      notes.push(`cross-checked ${balls.length} balls against ${csvPath}`);
    }
  }
}

// --------------------------------------------------------------------------
// 7. audit completeness gate
// --------------------------------------------------------------------------
if (unverified.length > 0) {
  const msg =
    `${unverified.length} BG256 balls still have a grid-derived (unverified) identity: ` +
    `${unverified.slice(0, 12).map((b) => b.ball).join(", ")}${unverified.length > 12 ? ", ..." : ""}. ` +
    `Cross-check against Lattice FPGA-SC-02034 with --lattice <csv>.`;
  if (allowIncomplete) notes.push(`AUDIT INCOMPLETE (allowed): ${msg}`);
  else fail(`FABRICATION BLOCKED: ${msg}`);
}

// --------------------------------------------------------------------------
// report
// --------------------------------------------------------------------------
for (const n of notes) console.log(`  · ${n}`);
if (failures.length) {
  console.error(`\nBGA256 identity verification FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log("\nBGA256 identity verification PASSED");
