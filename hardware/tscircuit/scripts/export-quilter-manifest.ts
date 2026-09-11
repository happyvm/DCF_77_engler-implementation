/**
 * Export the Quilter handoff manifest.
 *
 * docs/14-hardware-cad-tscircuit.md: "Quilter is not the source of electrical
 * intent" — the placement intent has to travel as data with the KiCad export.
 * This script turns the tables in src/board/hatplus_constraints.ts into
 * dist/circuit-json/placement-regions.json so the pre-Quilter review (and the
 * Quilter submission itself) can diff the constraints instead of reading TSX.
 *
 * Also emits dist/circuit-json/board-rules.json with the hard analog/digital
 * rules, routing priority order and keepouts.
 *
 * Usage: tsx scripts/export-quilter-manifest.ts
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildQuilterManifest } from "../src/board/quilter";
import { BOARD_MM, NET_PRIORITY, HARD_RULES } from "../src/board/hatplus_constraints";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const OUT_DIR = path.join(ROOT, "dist", "circuit-json");

fs.mkdirSync(OUT_DIR, { recursive: true });

const manifest = buildQuilterManifest("rev0");
const manifestPath = path.join(OUT_DIR, "placement-regions.json");
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

const rules = {
  revision: "rev0",
  board: BOARD_MM,
  routing_priority: NET_PRIORITY,
  hard_rules: HARD_RULES,
  keepouts: manifest.keepouts,
  locked_before_quilter: manifest.locked_placements.map((p) => p.ref),
  constrained_regions: manifest.regions.map((r) => r.id),
};
const rulesPath = path.join(OUT_DIR, "board-rules.json");
fs.writeFileSync(rulesPath, `${JSON.stringify(rules, null, 2)}\n`, "utf8");

console.log(`wrote ${path.relative(ROOT, manifestPath)}`);
console.log(`  locked placements : ${manifest.locked_placements.length}`);
console.log(`  regions           : ${manifest.regions.length}`);
console.log(`  keepouts          : ${manifest.keepouts.length}`);
console.log(`wrote ${path.relative(ROOT, rulesPath)}`);