/**
 * Courtyard calibration helper.
 *
 * The pre-Quilter placer in src/board/hatplus_constraints.ts works on declared
 * courtyard rectangles (SIZE_MM). Hand-estimating them under-declares the real
 * footprints and produces overlapping placements, so SIZE_MM is measured from the
 * footprints tscircuit actually renders:
 *
 *   npm run export:circuit
 *   tsx scripts/measure-courtyards.ts            # print a SIZE_MM table
 *   tsx scripts/measure-courtyards.ts --check    # fail if SIZE_MM is too small
 *
 * Method (in priority order, per component):
 *   1. the courtyard tscircuit itself renders — `pcb_courtyard_rect`, or the
 *      bounding box of `pcb_courtyard_outline`. This is the rectangle the DRC
 *      `pcb_courtyard_overlap_error` checks, so it is the ground truth and it
 *      wins when present;
 *   2. fallback when the footprint emits no courtyard element: pad bounding box
 *      (`pcb_smtpad` / `pcb_plated_hole`) + COURTYARD_ALLOWANCE_MM (0.7 mm);
 *   3. the declared size is always at least the pad bounding box.
 *
 * Using the pads alone under-declared every footprint whose silkscreen extends
 * beyond the pads (the BG256 in particular: pads measured 12.70 mm, the rendered
 * courtyard is 15.83 x 15.93 mm). That gap let the placer move a "12.7 mm" FPGA on
 * top of the configuration-flash cluster, so the calibration must read the real
 * courtyard, not an estimate.
 *
 * Usage: tsx scripts/measure-courtyards.ts [--check] [--circuit-json <path>]
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const ALLOWANCE_MM = 0.7;

const jsonArg = process.argv.indexOf("--circuit-json");
const CIRCUIT_JSON =
  jsonArg !== -1 && process.argv[jsonArg + 1]
    ? path.resolve(process.argv[jsonArg + 1])
    : path.join(ROOT, "dist", "circuit-json", "dcf77-hat.circuit.json");
const check = process.argv.includes("--check");

if (!fs.existsSync(CIRCUIT_JSON)) {
  console.error(`FATAL: ${CIRCUIT_JSON} not found — run \`npm run export:circuit\` first`);
  process.exit(1);
}

type El = Record<string, any>;
const circuit = JSON.parse(fs.readFileSync(CIRCUIT_JSON, "utf8")) as El[];

const nameOfSource = new Map<string, string>();
for (const el of circuit) {
  if (el.type === "source_component" && el.source_component_id) {
    nameOfSource.set(el.source_component_id, (el.name ?? el.source_component_id) as string);
  }
}
const nameOfPcb = new Map<string, string>();
for (const el of circuit) {
  if (el.type === "pcb_component" && el.pcb_component_id) {
    const n = nameOfSource.get(el.source_component_id) ?? el.name ?? el.pcb_component_id;
    nameOfPcb.set(el.pcb_component_id, (n as string).replace(/^\./, ""));
  }
}

const boxes = new Map<string, { l: number; r: number; b: number; t: number }>();
const grow = (ref: string, l: number, r: number, b: number, t: number) => {
  const box = boxes.get(ref) ?? { l: Infinity, r: -Infinity, b: Infinity, t: -Infinity };
  box.l = Math.min(box.l, l);
  box.r = Math.max(box.r, r);
  box.b = Math.min(box.b, b);
  box.t = Math.max(box.t, t);
  boxes.set(ref, box);
};
for (const el of circuit) {
  if (el.type !== "pcb_smtpad" && el.type !== "pcb_plated_hole") continue;
  const ref = nameOfPcb.get(el.pcb_component_id);
  if (!ref) continue;
  const od = Number(el.outer_diameter ?? 0);
  const w = Number(el.width ?? od ?? 0);
  const h = Number(el.height ?? od ?? 0);
  grow(ref, Number(el.x ?? 0) - w / 2, Number(el.x ?? 0) + w / 2, Number(el.y ?? 0) - h / 2, Number(el.y ?? 0) + h / 2);
}

// The courtyard tscircuit actually renders — the rectangle the DRC checks.
const rendered = new Map<string, { l: number; r: number; b: number; t: number }>();
const growRendered = (ref: string, l: number, r: number, b: number, t: number) => {
  const box = rendered.get(ref) ?? { l: Infinity, r: -Infinity, b: Infinity, t: -Infinity };
  box.l = Math.min(box.l, l);
  box.r = Math.max(box.r, r);
  box.b = Math.min(box.b, b);
  box.t = Math.max(box.t, t);
  rendered.set(ref, box);
};
for (const el of circuit) {
  if (el.type !== "pcb_courtyard_rect" && el.type !== "pcb_courtyard_outline") continue;
  const ref = nameOfPcb.get(el.pcb_component_id);
  if (!ref) continue;
  if (el.type === "pcb_courtyard_rect") {
    const w = Number(el.width ?? 0);
    const h = Number(el.height ?? 0);
    const cx = Number(el.center?.x ?? 0);
    const cy = Number(el.center?.y ?? 0);
    growRendered(ref, cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2);
  } else {
    for (const p of el.outline ?? []) {
      growRendered(ref, Number(p.x ?? 0), Number(p.x ?? 0), Number(p.y ?? 0), Number(p.y ?? 0));
    }
  }
}

const up = (v: number) => Math.ceil(v * 20) / 20;
const measured = new Map<string, [number, number]>();
const allRefs = new Set<string>([...boxes.keys(), ...rendered.keys()]);
for (const ref of [...allRefs].sort((a, c) => a.localeCompare(c))) {
  const pads = boxes.get(ref);
  const court = rendered.get(ref);
  // Declared courtyard = real courtyard when rendered, otherwise pads + allowance,
  // and never below the raw pad bounding box.
  const w = Math.max(court ? court.r - court.l : pads ? pads.r - pads.l + ALLOWANCE_MM : 0, pads ? pads.r - pads.l : 0);
  const h = Math.max(court ? court.t - court.b : pads ? pads.t - pads.b + ALLOWANCE_MM : 0, pads ? pads.t - pads.b : 0);
  measured.set(ref, [up(w), up(h)]);
}

if (!check) {
  console.log("  // measured courtyard sizes (rendered courtyard, else pad bbox + " + ALLOWANCE_MM + " mm), paste into SIZE_MM");
  let line = "  ";
  for (const [ref, [w, h]] of measured) {
    const item = `${ref}: [${w.toFixed(2)}, ${h.toFixed(2)}], `;
    if (line.length + item.length > 118) {
      console.log(line.trimEnd());
      line = "  ";
    }
    line += item;
  }
  if (line.trim()) console.log(line.trimEnd());
  console.log(`  // ${measured.size} components measured from ${path.relative(ROOT, CIRCUIT_JSON)}`);
  process.exit(0);
}

// --check: every region member must have a declared size at least as large as measured
const { REGIONS, sizeOf } = await import("../src/board/hatplus_constraints");
const failures: string[] = [];
for (const region of REGIONS) {
  for (const member of region.members) {
    const m = measured.get(member);
    if (!m) {
      failures.push(`"${member}" has no rendered footprint in ${path.basename(CIRCUIT_JSON)}`);
      continue;
    }
    const declared = sizeOf(member);
    if (declared[0] + 1e-9 < m[0] || declared[1] + 1e-9 < m[1]) {
      failures.push(
        `"${member}" declares [${declared.join(", ")}] but the rendered footprint measures ` +
        `[${m.join(", ")}] (incl. ${ALLOWANCE_MM} mm allowance)`,
      );
    }
  }
}
if (failures.length) {
  console.error(`Courtyard calibration FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log(`Courtyard calibration PASSED — ${measured.size} rendered components, all region members declared >= measured`);