/**
 * Supplier footprint gate (offline).
 *
 * Closes the `supplier_footprint_mismatch_warning` class that used to fire on
 * every 0402 passive (69 warnings, copper IoU 0.77 R / 0.72 C against a
 * threshold of 0.80). The fix is the audited JLCPCB land patterns in
 * src/parts/footprints.tsx, pinned per component through `supplierPartNumbers`.
 *
 * This gate re-derives the copper bounding box of every 0402 passive from the
 * emitted Circuit JSON and checks it against suppliers/jlcpcb-land-patterns.json,
 * and it fails if the build emits any `supplier_footprint_mismatch_warning`.
 *
 * Usage: npm run export:circuit && npm run check:footprints
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const CIRCUIT = path.join(ROOT, "dist", "circuit-json", "dcf77-hat.circuit.json");
const PATTERNS = path.join(ROOT, "suppliers", "jlcpcb-land-patterns.json");
const IOU_FLOOR = 0.95;

if (!fs.existsSync(CIRCUIT)) {
  console.error(`FATAL: ${path.relative(ROOT, CIRCUIT)} not found — run \`npm run export:circuit\` first`);
  process.exit(1);
}

type El = Record<string, any>;
const circuit = JSON.parse(fs.readFileSync(CIRCUIT, "utf8")) as El[];
const audit = JSON.parse(fs.readFileSync(PATTERNS, "utf8")) as {
  patterns: Record<
    string,
    { copper_bbox_mm: [number, number]; jlcpcb_parts: string[] }
  >;
};

const partToPattern = new Map<string, string>();
for (const [name, p] of Object.entries(audit.patterns)) {
  for (const part of p.jlcpcb_parts) partToPattern.set(part, name);
}

const failures: string[] = [];

// 1. no mismatch warning may survive in the emitted circuit
const mismatches = circuit.filter((e) => e.type === "supplier_footprint_mismatch_warning");
for (const m of mismatches) failures.push(`supplier_footprint_mismatch_warning survived: ${m.message}`);

// 2. every pinned 0402 passive must reproduce its audited land-pattern bbox
const sourceById = new Map<string, El>();
for (const e of circuit) if (e.type === "source_component") sourceById.set(e.source_component_id, e);
const pcbById = new Map<string, El>();
for (const e of circuit) if (e.type === "pcb_component") pcbById.set(e.pcb_component_id, e);
const padsByPcb = new Map<string, El[]>();
for (const e of circuit) {
  if (e.type !== "pcb_smtpad") continue;
  padsByPcb.set(e.pcb_component_id, [...(padsByPcb.get(e.pcb_component_id) ?? []), e]);
}

const bboxOf = (pads: El[]): [number, number] => {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const p of pads) {
    minX = Math.min(minX, Number(p.x) - Number(p.width) / 2);
    maxX = Math.max(maxX, Number(p.x) + Number(p.width) / 2);
    minY = Math.min(minY, Number(p.y) - Number(p.height) / 2);
    maxY = Math.max(maxY, Number(p.y) + Number(p.height) / 2);
  }
  return [maxX - minX, maxY - minY];
};
const iou = (a: [number, number], b: [number, number]) => {
  const inter = Math.min(a[0], b[0]) * Math.min(a[1], b[1]);
  const union = a[0] * a[1] + b[0] * b[1] - inter;
  return union > 0 ? inter / union : 0;
};

let checked = 0;
for (const [pcbId, pcb] of pcbById) {
  const source = sourceById.get(pcb.source_component_id);
  const pinned = source?.supplier_part_numbers?.jlcpcb?.[0];
  if (!pinned) continue;
  const patternName = partToPattern.get(pinned);
  if (!patternName) continue;
  const pads = padsByPcb.get(pcbId) ?? [];
  if (pads.length === 0) {
    failures.push(`${source.name} (${pinned}) has no copper pads in the export`);
    continue;
  }
  const measured = bboxOf(pads);
  const expect = audit.patterns[patternName].copper_bbox_mm;
  const score = iou(measured, expect);
  if (score < IOU_FLOOR) {
    failures.push(
      `${source.name} (${pinned}, ${patternName}) copper bbox ` +
        `${measured[0].toFixed(4)} x ${measured[1].toFixed(4)} mm vs audited ` +
        `${expect[0]} x ${expect[1]} mm (IoU ${score.toFixed(4)} < ${IOU_FLOOR})`,
    );
  }
  checked++;
}

if (failures.length) {
  console.error(`Supplier footprint gate FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log(
  `Supplier footprint gate PASSED — ${checked} pinned passives match their audited ` +
    `JLCPCB land pattern, 0 supplier_footprint_mismatch_warning`,
);
