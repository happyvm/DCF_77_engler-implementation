/**
 * Reproducible re-audit of the JLCPCB passive land patterns.
 *
 * Reads suppliers/jlcpcb-land-patterns.json, re-fetches every listed part from the
 * EasyEDA component API and compares the copper bounding box it reports with the
 * recorded one. `--write` refreshes the recorded geometry.
 *
 * The copper bbox is exactly what @tscircuit/core compares in
 * getBestBoundsIou (pcb_smtpad + pcb_plated_hole bounds), so this is the number
 * that decides whether src/parts/footprints.tsx reproduces the supplier land
 * pattern.
 *
 * Network + EasyEDA rate limits apply; this is a manual audit tool, not part of
 * `npm run check`.
 *
 * Usage:
 *   tsx scripts/audit-supplier-footprints.ts            # verify, exit 1 on drift
 *   tsx scripts/audit-supplier-footprints.ts --write     # refresh the JSON
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");
const FILE = path.join(ROOT, "suppliers", "jlcpcb-land-patterns.json");
const write = process.argv.includes("--write");
const UNIT_MM = 0.254; // EasyEDA internal unit (10 mil)

const HEADERS: Record<string, string> = {
  accept: "application/json, text/javascript, */*; q=0.01",
  "x-requested-with": "XMLHttpRequest",
  referer: "https://easyeda.com/editor",
  "user-agent":
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36",
};

type LandPattern = {
  package: string;
  description: string;
  copper_bbox_mm: [number, number];
  jlcpcb_parts: string[];
  pads: { port: string; shape: string; width_mm: number; height_mm: number; x_mm: number; y_mm: number }[];
  courtyard_mm: [number, number];
  generic_0402_iou?: number;
  source_package?: string;
};

const audit = JSON.parse(fs.readFileSync(FILE, "utf8")) as {
  patterns: Record<string, LandPattern>;
};

async function resolveUuid(pn: string): Promise<string> {
  const body =
    "type=3&doctype%5B%5D=2&uid=0819f05c4eef4c71ace90d822a990e87" +
    `&returnListStyle=classifyarr&wd=${pn}&version=6.4.7`;
  const res = await fetch("https://easyeda.com/api/components/search", {
    method: "POST",
    headers: { ...HEADERS, "content-type": "application/x-www-form-urlencoded; charset=UTF-8", origin: "https://easyeda.com" },
    body,
  });
  if (!res.ok) throw new Error(`EasyEDA search ${pn}: HTTP ${res.status}`);
  const json: any = await res.json();
  const hit = (json?.result?.lists?.lcsc ?? []).find((it: any) => it?.lcsc?.number === pn);
  if (!hit) throw new Error(`EasyEDA search ${pn}: no LCSC hit`);
  return hit.uuid as string;
}

async function fetchPackage(pn: string) {
  const uuid = await resolveUuid(pn);
  const res = await fetch(
    `https://easyeda.com/api/components/${uuid}?version=6.4.7&uuid=${uuid}&datastrid=`,
    { headers: HEADERS },
  );
  if (!res.ok) throw new Error(`EasyEDA component ${pn}: HTTP ${res.status}`);
  const json: any = await res.json();
  const shapes: string[] = json?.result?.packageDetail?.dataStr?.shape ?? [];
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  const pads = [];
  for (const s of shapes) {
    if (typeof s !== "string" || !s.startsWith("PAD~")) continue;
    const f = s.split("~");
    const cx = Number(f[2]), cy = Number(f[3]), w = Number(f[4]), h = Number(f[5]);
    minX = Math.min(minX, cx - w / 2);
    maxX = Math.max(maxX, cx + w / 2);
    minY = Math.min(minY, cy - h / 2);
    maxY = Math.max(maxY, cy + h / 2);
    pads.push({ cx, cy, w, h });
  }
  if (!Number.isFinite(minX)) throw new Error(`EasyEDA component ${pn}: no PAD copper`);
  const round = (v: number) => Math.round(v * 10000) / 10000;
  return {
    width: round((maxX - minX) * UNIT_MM),
    height: round((maxY - minY) * UNIT_MM),
    pads: pads.map((p, i) => ({
      port: String(i + 1),
      shape: "rect",
      width_mm: round(p.w * UNIT_MM),
      height_mm: round(p.h * UNIT_MM),
      x_mm: round((p.cx - (minX + maxX) / 2) * UNIT_MM),
      y_mm: round((p.cy - (minY + maxY) / 2) * UNIT_MM),
    })),
    packageName: json?.result?.packageDetail?.title as string | undefined,
  };
}

const failures: string[] = [];
let checked = 0;
for (const [name, pattern] of Object.entries(audit.patterns)) {
  const reports: { pn: string; width: number; height: number; pads: any[]; packageName?: string }[] = [];
  for (const pn of pattern.jlcpcb_parts) {
    try {
      const r = await fetchPackage(pn);
      reports.push({ pn, ...r });
    } catch (err) {
      // A single unlisted/unavailable package must not abort the audit.
      console.log(`  · ${name} ${pn}: skipped (${(err as Error).message})`);
    }
  }
  if (reports.length === 0) {
    failures.push(`${name}: no part could be re-fetched`);
    continue;
  }
  const bbox = new Set(reports.map((r) => `${r.width}x${r.height}`));
  if (bbox.size > 1) {
    failures.push(`${name}: parts disagree on copper bbox (${[...bbox].join(", ")})`);
  }
  const [w, h] = pattern.copper_bbox_mm;
  const mismatched = reports.filter((r) => Math.abs(r.width - w) > 0.01 || Math.abs(r.height - h) > 0.01);
  if (mismatched.length) {
    failures.push(
      `${name}: recorded ${w} x ${h} mm but ` +
        mismatched.map((r) => `${r.pn} reports ${r.width} x ${r.height}`).join(", "),
    );
  }
  checked += reports.length;
  if (write) {
    const ref = reports[0];
    pattern.copper_bbox_mm = [ref.width, ref.height];
    pattern.pads = ref.pads;
    pattern.source_package = ref.packageName;
  }
  console.log(`  ✓ ${name}: ${reports.length} part(s), copper ${[...bbox].join(" / ")} mm`);
}

if (write) {
  fs.writeFileSync(FILE, JSON.stringify(audit, null, 2) + "\n");
  console.log(`\nupdated ${path.relative(ROOT, FILE)} (${checked} parts re-fetched)`);
  process.exit(0);
}

if (failures.length) {
  console.error(`\nLand-pattern audit FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  ✗ ${f}`);
  process.exit(1);
}
console.log(`\nLand-pattern audit PASSED — ${checked} parts re-fetched, geometry unchanged`);
