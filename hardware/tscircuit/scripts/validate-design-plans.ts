/**
 * Design-plan gate — pin plan + power plan + placement constraints.
 *
 * docs/14-hardware-cad-tscircuit.md requires the tscircuit source to be checked
 * against the machine-readable plans (pin-plan.json, power-plan.json) and to have
 * the locked placements/constrained regions expressed as real constraints, not
 * comments. This script is that gate. It exits non-zero on any drift.
 *
 * Checks
 *   1. pin-plan.json: 256 BG256 balls, complete A..T (no I/O/Q/S) x 1..16 grid,
 *      row-major pad numbering from the top-left corner, frozen identity SHA-256,
 *      and presence of every documented signal + power ball group.
 *   2. power-plan.json: the declared rails are exactly the `rail_*` nets the
 *      schematic uses (src/parts/nets.ts), and the sequencing list is non-empty.
 *   3. regions: every declared member is placed, inside its region, and no two
 *      parts on the board overlap (Placer.PLACER.clearance honoured).
 *   4. locked placements: each one is inside the region it declares.
 *   5. MANDATORY_RELATIONS: each emitted <constraint> is actually satisfied by
 *      the coordinates (edge-to-edge distances).
 *   6. the whole design fits the HAT+ outline.
 *
 * Usage: tsx scripts/validate-design-plans.ts
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import {
  BOARD_MM,
  HAT_HEADER,
  LOCKED_PLACEMENTS,
  MANDATORY_RELATIONS,
  PLACER,
  REGIONS,
  boardObstacles,
  pos,
  rectOf,
  sizeOf,
  type Rect,
  type Region,
  type RegionId,
} from "../src/board/hatplus_constraints";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const EPS = 1e-6;

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

const failures: string[] = [];
const notes: string[] = [];
const fail = (msg: string) => failures.push(msg);
const check = (cond: boolean, msg: string) => {
  if (!cond) fail(msg);
  return cond;
};

// ---------------------------------------------------------------------------
// 1. pin plan
// ---------------------------------------------------------------------------
const ROW_LETTERS = [..."ABCDEFGHJKLMNPRT"];
const pinPlan = JSON.parse(fs.readFileSync(path.join(ROOT, "pin-plan.json"), "utf8")) as {
  device: string;
  package: string;
  ball_audit?: { identity_sha256?: string };
  balls?: Ball[];
};

check(pinPlan.device === "LFE5U-45F-7BG256I", `pin-plan device is "${pinPlan.device}", expected LFE5U-45F-7BG256I`);
check(pinPlan.package === "BG256", `pin-plan package is "${pinPlan.package}", expected BG256`);
const balls = pinPlan.balls ?? [];
check(balls.length === 256, `pin-plan.json has ${balls.length} balls, expected 256`);

const ordered = [...balls].sort((a, b) => a.pad - b.pad);
const seen = new Set<string>();
ordered.forEach((b, i) => {
  const expRow = ROW_LETTERS[Math.floor(i / 16)];
  const expCol = (i % 16) + 1;
  check(b.pad === i + 1, `pad numbering gap at index ${i}: pad=${b.pad}`);
  check(b.ball === `${expRow}${expCol}`, `pad ${i + 1} is "${b.ball}", row-major top-left order requires "${expRow}${expCol}"`);
  check(b.row === expRow && b.col === expCol, `ball "${b.ball}" row/col (${b.row},${b.col}) inconsistent with its name`);
  check(!seen.has(b.ball), `duplicate ball "${b.ball}"`);
  seen.add(b.ball);
});
check(seen.size === 256, `pin-plan covers ${seen.size}/256 ball names`);

const canonical = ordered
  .map(
    (b) =>
      `${b.pad}:${b.ball}:${b.row}${b.col}:${b.pin_name ?? ""}:${b.lattice_bank ?? ""}:${b.signal ?? ""}:${b.kind}`,
  )
  .join("\n");
const digest = crypto.createHash("sha256").update(canonical, "utf8").digest("hex");
check(
  digest === pinPlan.ball_audit?.identity_sha256,
  `ball identity SHA-256 drifted: computed ${digest}, pin-plan declares ${pinPlan.ball_audit?.identity_sha256}`,
);
notes.push(`pin-plan: 256 balls, identity sha256 ${digest.slice(0, 16)}…`);

const REQUIRED_SIGNALS = [
  "CLK_25M", "ADC_SCK", "ADC_SDO", "ADC_CONV", "PGA_SCK", "PGA_MOSI", "PGA_CS_N",
  "PPS_REF", "LCD_SCL", "LCD_SDA", "LCD_RST_N", "LCD_BL_EN",
  "HAT_SPI_MOSI", "HAT_SPI_MISO", "HAT_SPI_SCLK", "HAT_SPI_CS_N", "HAT_IRQ",
  "HAT_RESET_N", "HAT_PPS", "HAT_UART_TX", "HAT_UART_RX",
];
const bySignal = new Map<string, Ball>();
for (const b of balls) if (b.signal) bySignal.set(b.signal, b);
for (const s of REQUIRED_SIGNALS) check(bySignal.has(s), `documented signal "${s}" missing from pin-plan.json`);
for (const rail of ["VCC", "VCCAUX", "VCCIO0", "VCCIO1", "VCCIO2", "VCCIO3", "VCCIO6", "VCCIO7", "VCCIO8"]) {
  check(bySignal.has(rail), `power ball group "${rail}" missing from pin-plan.json`);
}
const FROZEN_BALLS: Record<string, string> = {
  CLK_25M: "C9", ADC_SCK: "J16", ADC_SDO: "J15", ADC_CONV: "K16", PGA_SCK: "H12",
  PGA_MOSI: "H13", PGA_CS_N: "J12", PPS_REF: "R12", LCD_SCL: "M13", LCD_SDA: "N14",
  LCD_RST_N: "M14", LCD_BL_EN: "R13", HAT_SPI_MOSI: "A10", HAT_SPI_MISO: "D11",
  HAT_SPI_SCLK: "A9", HAT_SPI_CS_N: "E11", HAT_IRQ: "C12", HAT_RESET_N: "B12",
  HAT_PPS: "A11", HAT_UART_TX: "A13", HAT_UART_RX: "A14",
};
for (const [sig, ball] of Object.entries(FROZEN_BALLS)) {
  const got = bySignal.get(sig)?.ball;
  check(got === ball, `${sig} is on ball ${got}, frozen identity requires ${ball}`);
}

// ---------------------------------------------------------------------------
// 2. power plan <-> schematic rail nets
// ---------------------------------------------------------------------------
const powerPlan = JSON.parse(fs.readFileSync(path.join(ROOT, "power-plan.json"), "utf8")) as {
  rails?: Record<string, unknown>;
  sequencing?: unknown[];
};
const declaredRails = Object.keys(powerPlan.rails ?? {});
check(declaredRails.length > 0, "power-plan.json declares no rails");
check((powerPlan.sequencing ?? []).length > 0, "power-plan.json has an empty sequencing list");

const netsSrc = fs.readFileSync(path.join(ROOT, "src", "parts", "nets.ts"), "utf8");
const schematicRails = new Set(
  [...netsSrc.matchAll(/rail_([A-Za-z0-9_]+)/g)].map((m) => m[1]),
);
// The Raspberry Pi supplies enter the HAT at power-plan.json § hat_input (vin/vbias/on)
// rather than as derived rails, so they are not keys of § rails.
const HAT_INPUT_RAILS = ["PI_5V", "PI_3V3"];
const powerPlanText = JSON.stringify(powerPlan);
for (const rail of HAT_INPUT_RAILS) {
  check(powerPlanText.includes(rail), `HAT input rail "${rail}" is not referenced anywhere in power-plan.json`);
}
for (const rail of declaredRails) {
  check(schematicRails.has(rail), `power-plan rail "${rail}" has no rail_${rail} net in src/parts/nets.ts`);
}
for (const rail of schematicRails) {
  check(
    declaredRails.includes(rail) || HAT_INPUT_RAILS.includes(rail),
    `schematic rail_${rail} net is declared neither in power-plan.json § rails nor as a HAT input rail`,
  );
}
notes.push(
  `power-plan: ${declaredRails.length} derived rails + ${HAT_INPUT_RAILS.length} HAT input rails matched 1:1 with schematic rail nets`,
);

// ---------------------------------------------------------------------------
// 3..5 placement tables
// ---------------------------------------------------------------------------
const rects = new Map<string, { rect: Rect; region: RegionId }>();
const dupRefs: string[] = [];
for (const region of REGIONS as Region[]) {
  for (const member of region.members) {
    const p = pos(region.id, member);
    const [w, h] = sizeOf(member);
    if (rects.has(member)) dupRefs.push(member);
    rects.set(member, { rect: rectOf(p.pcbX, p.pcbY, w, h), region: region.id });
  }
}
for (const ref of new Set(dupRefs)) fail(`ref "${ref}" is declared in more than one region`);

// 3a. region containment
for (const region of REGIONS as Region[]) {
  const L = region.x - region.width / 2;
  const R = region.x + region.width / 2;
  const B = region.y - region.height / 2;
  const T = region.y + region.height / 2;
  for (const member of region.members) {
    const r = rects.get(member)!.rect;
    if (r.left < L - EPS || r.right > R + EPS || r.bottom < B - EPS || r.top > T + EPS) {
      fail(
        `"${member}" is outside region "${region.id}": part [${r.left},${r.right}]x[${r.bottom},${r.top}] ` +
        `vs region [${L},${R}]x[${B},${T}]`,
      );
    }
  }
}
notes.push(`regions: ${REGIONS.length} regions, ${rects.size} placed parts, all contained`);

// 3b. no two parts overlap (board-wide)
const refList = [...rects.entries()];
for (let i = 0; i < refList.length; i++) {
  for (let j = i + 1; j < refList.length; j++) {
    const [ra, a] = refList[i];
    const [rb, b] = refList[j];
    const hit =
      a.rect.left < b.rect.right - EPS &&
      a.rect.right > b.rect.left + EPS &&
      a.rect.bottom < b.rect.top - EPS &&
      a.rect.top > b.rect.bottom + EPS;
    if (hit) fail(`overlap between "${ra}" (${a.region}) and "${rb}" (${b.region}) at declared courtyards`);
  }
}

// 3c. placer clearance still honoured between neighbours of the same region
for (const region of REGIONS as Region[]) {
  for (let i = 0; i < region.members.length; i++) {
    for (let j = i + 1; j < region.members.length; j++) {
      const a = rects.get(region.members[i])!.rect;
      const b = rects.get(region.members[j])!.rect;
      const gapX = Math.max(b.left - a.right, a.left - b.right);
      const gapY = Math.max(b.bottom - a.top, a.bottom - b.top);
      const gap = Math.max(gapX, gapY);
      if (gap < PLACER.clearance - 0.05) {
        fail(
          `"${region.members[i]}" and "${region.members[j]}" are only ${gap.toFixed(2)}mm apart in ` +
          `"${region.id}", PLACER.clearance is ${PLACER.clearance}mm`,
        );
      }
    }
  }
}

// 3d. no part lands on a mechanical obstacle (HAT header / mounting holes)
for (const obstacle of boardObstacles()) {
  for (const [ref, { rect }] of rects) {
    const hit =
      rect.left < obstacle.rect.right - EPS &&
      rect.right > obstacle.rect.left + EPS &&
      rect.bottom < obstacle.rect.top - EPS &&
      rect.top > obstacle.rect.bottom + EPS;
    if (hit) fail(`"${ref}" overlaps the mechanical obstacle ${obstacle.ref}`);
  }
}
notes.push(`mechanical obstacles: header + 4 mounting holes clear of every placed part`);

// 4. locked placements inside their declared region
for (const [ref, p] of Object.entries(LOCKED_PLACEMENTS)) {
  const region = REGIONS.find((r) => r.id === p.region);
  if (!region) {
    fail(`locked ref "${ref}" declares unknown region "${p.region}"`);
    continue;
  }
  if (!region.members.includes(ref)) {
    fail(`locked ref "${ref}" is not listed in the members of region "${p.region}"`);
  }
  const placed = rects.get(ref)?.rect;
  if (!placed) {
    fail(`locked ref "${ref}" has no placement`);
    continue;
  }
  const cx = (placed.left + placed.right) / 2;
  const cy = (placed.bottom + placed.top) / 2;
  check(Math.abs(cx - p.x) < 1e-6, `locked ref "${ref}" is placed at x=${cx}, table says ${p.x}`);
  check(Math.abs(cy - p.y) < 1e-6, `locked ref "${ref}" is placed at y=${cy}, table says ${p.y}`);
}
notes.push(`locked placements: ${Object.keys(LOCKED_PLACEMENTS).length} verified inside their region`);

// 5. mandatory relations satisfied by the real coordinates
const headerRect: Rect = rectOf(HAT_HEADER.x, HAT_HEADER.y, 48.26 + 1.8, 2.54 + 1.8);
const rectOfRef = (raw: string): Rect | null => {
  const ref = raw.replace(/^\./, "");
  if (ref === HAT_HEADER.ref) return headerRect;
  return rects.get(ref)?.rect ?? null;
};
for (const rel of MANDATORY_RELATIONS) {
  if (rel.kind === "sameY" || rel.kind === "sameX") {
    const rs = rel.for.map(rectOfRef);
    if (rs.some((r) => !r)) {
      fail(`relation ${rel.kind} references an unknown ref: ${rel.for.join(", ")}`);
      continue;
    }
    const centers = (rs as Rect[]).map((r) => (rel.kind === "sameY" ? (r.bottom + r.top) / 2 : (r.left + r.right) / 2));
    const spread = Math.max(...centers) - Math.min(...centers);
    check(spread < 1e-6, `relation sameY/sameX ${rel.for.join("=")} is off by ${spread.toFixed(3)}mm (${rel.why})`);
  } else if (rel.kind === "xDist") {
    const l = rectOfRef(rel.left);
    const r = rectOfRef(rel.right);
    if (!l || !r) {
      fail(`relation xDist references an unknown ref: ${rel.left} / ${rel.right}`);
      continue;
    }
    const d = r.left - l.right;
    check(d >= rel.xDist - EPS, `xDist(${rel.left}, ${rel.right}) = ${d.toFixed(2)}mm < ${rel.xDist}mm (${rel.why})`);
  } else {
    const t = rectOfRef(rel.top);
    const b = rectOfRef(rel.bottom);
    if (!t || !b) {
      fail(`relation yDist references an unknown ref: ${rel.top} / ${rel.bottom}`);
      continue;
    }
    const d = t.bottom - b.top;
    check(d >= rel.yDist - EPS, `yDist(${rel.top}, ${rel.bottom}) = ${d.toFixed(2)}mm < ${rel.yDist}mm (${rel.why})`);
  }
}
notes.push(`mandatory relations: ${MANDATORY_RELATIONS.length} checked against the emitted coordinates`);

// 6. board containment
for (const [ref, { rect }] of rects) {
  const halfW = BOARD_MM.width / 2;
  const halfH = BOARD_MM.height / 2;
  if (rect.left < -halfW - EPS || rect.right > halfW + EPS || rect.bottom < -halfH - EPS || rect.top > halfH + EPS) {
    fail(`"${ref}" falls outside the ${BOARD_MM.width}x${BOARD_MM.height}mm HAT+ outline`);
  }
}
notes.push(`board: all parts inside the ${BOARD_MM.width}x${BOARD_MM.height}mm HAT+ outline`);

// ---------------------------------------------------------------------------
// report
// ---------------------------------------------------------------------------
for (const n of notes) console.log(`  · ${n}`);
if (failures.length) {
  console.error(`\nDesign-plan validation FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log("\nDesign-plan validation PASSED");