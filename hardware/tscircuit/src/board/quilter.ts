/**
 * Quilter handoff manifest.
 *
 * docs/14-hardware-cad-tscircuit.md requires the placement intent to travel with
 * the KiCad export, because "Quilter is not the source of electrical intent".
 *
 * This module turns the tables in hatplus_constraints.ts into
 *   - machine-readable JSON archived under dist/ (placement-regions.json), and
 *   - fabrication-layer annotation rectangles emitted on the PCB so the regions
 *     are visible in the pre-Quilter KiCad review.
 */
import {
  BOARD_MM,
  HARD_RULES,
  LOCKED_PLACEMENTS,
  MANDATORY_RELATIONS,
  MOUNTING_HOLES,
  NET_PRIORITY,
  REGIONS,
  regionById,
  type Region,
  type RegionId,
} from "./hatplus_constraints";

export type QuilterManifest = {
  revision: string;
  generator: string;
  board: typeof BOARD_MM;
  mounting_holes: typeof MOUNTING_HOLES;
  locked_placements: Array<{
    ref: string;
    x: number;
    y: number;
    rotation: number;
    region: string;
    reason: string;
  }>;
  regions: Array<{
    id: string;
    name: string;
    quilter: "optimise";
    bounds: { x: number; y: number; width: number; height: number };
    rules: string[];
    members: string[];
  }>;
  keepouts: Array<{
    id: string;
    purpose: string;
    bounds: { x: number; y: number; width: number; height: number };
    forbidden: string[];
  }>;
  routing_priority: string[];
  hard_rules: string[];
  mandatory_relations: typeof MANDATORY_RELATIONS;
};

/** Region bounds (lower-left corner + size) as Quilter keepout rectangles. */
function boundsOf(id: RegionId) {
  const r = regionById(id);
  return { x: r.x - r.width / 2, y: r.y - r.height / 2, width: r.width, height: r.height };
}

/** Regions Quilter must treat as electrically quiet (no routing of the listed nets). */
export const KEEPOUTS = [
  {
    id: "keepout_ferrite",
    purpose: "quiet ferrite / tuned-node zone",
    bounds: { x: -32.5, y: -23.5, width: 15.5, height: 20.5 },
    forbidden: ["fast Pi/FPGA traces", "switching-regulator nodes", "ECP5 clocks", "ADC SCK", "ground/power switching-current traces"],
  },
  {
    id: "keepout_tcxo",
    purpose: "TCXO isolation from ferrite / first analog stage",
    // derived from the tcxo region so it can never drift from the floorplan
    bounds: boundsOf("tcxo"),
    forbidden: ["ferrite coupling", "AFE first-stage traces", "buck switch node"],
  },
  {
    id: "keepout_buck_hotloop",
    purpose: "1.1 V buck hot loop confined to the digital power region",
    // derived from the power_1v1 region so it can never drift from the floorplan
    bounds: boundsOf("power_1v1"),
    forbidden: ["AFE", "TCXO", "ADC reference network"],
  },
];

export function buildQuilterManifest(revision = "rev0"): QuilterManifest {
  return {
    revision,
    generator: "hardware/tscircuit/src/board/quilter.ts",
    board: BOARD_MM,
    mounting_holes: MOUNTING_HOLES,
    locked_placements: Object.entries(LOCKED_PLACEMENTS).map(([ref, p]) => ({
      ref,
      x: p.x,
      y: p.y,
      rotation: p.rotation ?? 0,
      region: p.region,
      reason: p.reason,
    })),
    regions: REGIONS.map((r: Region) => ({
      id: r.id,
      name: r.name,
      quilter: r.quilter,
      bounds: { x: r.x - r.width / 2, y: r.y - r.height / 2, width: r.width, height: r.height },
      rules: r.rules,
      members: r.members,
    })),
    keepouts: KEEPOUTS,
    routing_priority: NET_PRIORITY,
    hard_rules: HARD_RULES,
    mandatory_relations: MANDATORY_RELATIONS,
  };
}
