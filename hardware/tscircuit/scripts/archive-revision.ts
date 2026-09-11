/**
 * Archive the revision metadata required by docs/14 "Version/reproducibility
 * policy": git commit SHA, pinned tool versions, and the checksums of every
 * generated artifact.
 *
 * Writes dist/REVISION.json. Run it AFTER the source commit — see
 * hardware/tscircuit/README.md § Reproducibility for the two-commit sequence.
 *
 * Usage: tsx scripts/archive-revision.ts
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");

function git(args: string[]): string {
  return execFileSync("git", args, { cwd: ROOT, encoding: "utf8" }).trim();
}

function sha256(file: string): string | null {
  if (!fs.existsSync(file)) return null;
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function installedVersion(pkg: string): string | null {
  const p = path.join(ROOT, "node_modules", pkg, "package.json");
  if (!fs.existsSync(p)) return null;
  return (JSON.parse(fs.readFileSync(p, "utf8")) as { version: string }).version;
}

const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8")) as {
  dependencies: Record<string, string>;
  devDependencies: Record<string, string>;
  engines?: { node?: string };
};

const artifacts = [
  "dist/circuit-json/dcf77-hat.circuit.json",
  "dist/kicad-pre-quilter/dcf77-hat.zip",
  "dist/circuit-json/placement-regions.json",
  "dist/circuit-json/board-rules.json",
].map((rel) => ({
  path: rel,
  present: fs.existsSync(path.join(ROOT, rel)),
  bytes: fs.existsSync(path.join(ROOT, rel)) ? fs.statSync(path.join(ROOT, rel)).size : null,
  sha256: sha256(path.join(ROOT, rel)),
}));

const revision = {
  revision: "rev0",
  board: "raspberry_pi_hatplus",
  generated_at: new Date().toISOString(),
  git: {
    commit: git(["rev-parse", "HEAD"]),
    commit_short: git(["rev-parse", "--short", "HEAD"]),
    branch: git(["rev-parse", "--abbrev-ref", "HEAD"]),
    // files outside hardware/tscircuit are owned by other tickets; the archive
    // only claims the source tree that produced these artifacts
    source_path: "hardware/tscircuit",
    source_dirty: git(["status", "--porcelain", "--", "."]).length > 0,
  },
  toolchain: {
    node: process.version,
    tscircuit: installedVersion("tscircuit") ?? pkg.devDependencies?.tscircuit ?? null,
    tscircuit_pinned: pkg.devDependencies?.tscircuit ?? null,
    tscircuit_core: installedVersion("@tscircuit/core") ?? pkg.dependencies?.["@tscircuit/core"] ?? null,
    tscircuit_core_pinned: pkg.dependencies?.["@tscircuit/core"] ?? null,
    tsx: installedVersion("tsx") ?? pkg.devDependencies?.tsx ?? null,
    engines_node: pkg.engines?.node ?? null,
  },
  artifacts,
  notes: [
    "dist/kicad-pre-quilter/dcf77-hat.zip is the pre-Quilter KiCad interchange archive (review + Quilter input), not a released fabrication package.",
    "Post-Quilter KiCad + Gerbers/BOM/PnP are archived separately under dist/kicad-post-quilter/ and dist/fabrication/ once a Quilter run is reviewed.",
  ],
};

const out = path.join(ROOT, "dist", "REVISION.json");
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify(revision, null, 2)}\n`, "utf8");

console.log(`wrote dist/REVISION.json (commit ${revision.git.commit_short})`);
for (const a of artifacts) {
  console.log(`  ${a.present ? "ok  " : "MISS"} ${a.path}${a.sha256 ? ` sha256=${a.sha256.slice(0, 16)}…` : ""}`);
}