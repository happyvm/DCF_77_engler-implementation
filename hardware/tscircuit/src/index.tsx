/**
 * DCF77 Engeler receiver Rev.0 — Raspberry Pi Standard HAT+ (tscircuit root).
 *
 * This file is the hardware source of truth for the electrical design intent:
 * connectivity, components/footprints, HAT+ mechanics, RF/mechanical keepouts,
 * mandatory placement relationships, net/priority intent and power-domain intent
 * (docs/14 "Source-of-truth rule").
 *
 * Build:   npx tsci build src/index.tsx
 * Export:  npx tsci export src/index.tsx -f kicad_zip -o dist/kicad-pre-quilter/dcf77-hat.zip
 * Gate:    npx tsx scripts/verify-bga-identity.ts        (ball identity, fails on renumbering)
 *          npx tsx scripts/validate-design-plans.ts      (pin plan + power plan + regions)
 */
import { ReceiverCore } from "./core/receiver_core";
import { AnalogRailBranch, CoreBuck, DigitalRails } from "./core/receiver_power";
import { Hat5vInput } from "./power/hat_5v_input";
import { HatHeader, HatIdEeprom } from "./board/raspberry_pi_hatplus";
import { RaspberryPiSpi } from "./host/rpi_spi";
import {
  BOARD_MM,
  MANDATORY_RELATIONS,
  REGIONS,
  type Relation,
} from "./board/hatplus_constraints";

/** Mandatory placement relations, emitted as first-class tscircuit constraints. */
function MandatoryConstraints() {
  return (
    <>
      {MANDATORY_RELATIONS.map((rel: Relation, i: number) => {
        if (rel.kind === "sameY") {
          return <constraint key={`c${i}`} pcb sameY for={rel.for} />;
        }
        if (rel.kind === "sameX") {
          return <constraint key={`c${i}`} pcb sameX for={rel.for} />;
        }
        if (rel.kind === "xDist") {
          return (
            <constraint
              key={`c${i}`}
              pcb
              xDist={`${rel.xDist}mm`}
              left={rel.left}
              right={rel.right}
              {...(rel.edgeToEdge ? { edgeToEdge: true as const } : {})}
            />
          );
        }
        return (
          <constraint
            key={`c${i}`}
            pcb
            yDist={`${rel.yDist}mm`}
            top={rel.top}
            bottom={rel.bottom}
            {...(rel.edgeToEdge ? { edgeToEdge: true as const } : {})}
          />
        );
      })}
    </>
  );
}

/**
 * The constrained regions are drawn as fabrication notes so the pre-Quilter KiCad
 * review sees where Quilter is allowed to optimise. The same table is exported
 * machine-readably to dist/circuit-json/placement-regions.json by
 * scripts/export-quilter-manifest.ts, and asserted by scripts/validate-design-plans.ts
 * (region containment + locked placements).
 */
function RegionAnnotations() {
  return (
    <>
      {REGIONS.map((r, i) => (
        <fabricationnoterect
          key={`region${i}`}
          name={`REGION_${r.id.toUpperCase()}`}
          pcbX={r.x}
          pcbY={r.y}
          width={`${r.width}mm`}
          height={`${r.height}mm`}
          color="blue"
        />
      ))}
    </>
  );
}

export default function Dcf77HatPlus() {
  return (
    <board
      width={`${BOARD_MM.width}mm`}
      height={`${BOARD_MM.height}mm`}
      thickness={`${BOARD_MM.thickness}mm`}
      layers={BOARD_MM.layers}
      title="DCF77 Engeler receiver Rev.0 — Raspberry Pi Standard HAT+"
    >
      {/* HAT+ mechanics and Raspberry Pi interface */}
      <HatHeader />
      <HatIdEeprom />
      <RaspberryPiSpi />

      {/* power tree */}
      <Hat5vInput />
      <AnalogRailBranch />
      <CoreBuck />
      <DigitalRails />

      {/* receiver */}
      <ReceiverCore />

      {/* constraints and region annotations (docs/14 "Locked before Quilter" / "Constrained regions") */}
      <MandatoryConstraints />
      <RegionAnnotations />
    </board>
  );
}
