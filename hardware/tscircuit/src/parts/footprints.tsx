/**
 * Audited supplier land patterns for the passive classes that used to be flagged
 * by `supplier_footprint_mismatch_warning`.
 *
 * The generic tscircuit footprinter `0402` copper bbox is 1.56 x 0.64 mm, while
 * the JLCPCB / EasyEDA `R0402` and `C0402` packages are 1.4313 x 0.54 mm and
 * 1.3402 x 0.54 mm respectively. That copper gap is what drove the copper IoU to
 * 0.7741 (R) / 0.7249 (C) against the warning threshold of 0.80, so the
 * resolved parts could never be released cleanly.
 *
 * These elements reproduce the audited geometry exactly, so a passive declared
 * with one of them and pinned to its `supplierPartNumbers` resolves to the same
 * copper bounding box and the warning disappears. The courtyard is kept at the
 * footprinter value (1.86 x 0.94 mm) so the placement planner and SIZE_MM
 * declarations in board/hatplus_constraints.ts do not shift.
 *
 * Provenance: suppliers/jlcpcb-land-patterns.json
 */
const COURTYARD = { width: "1.86mm", height: "0.94mm" } as const;

/** 0402 chip resistor, JLCPCB R0402 land pattern (copper 1.4313 x 0.54 mm). */
export const FP0402_RES = (
  <footprint>
    <smtpad portHints={["1"]} shape="rect" width="0.565658mm" height="0.540004mm" pcbX={-0.432816} pcbY={0} />
    <smtpad portHints={["2"]} shape="rect" width="0.565658mm" height="0.540004mm" pcbX={0.432816} pcbY={0} />
    <courtyardrect width={COURTYARD.width} height={COURTYARD.height} />
  </footprint>
);

/** 0402 chip capacitor, JLCPCB C0402 land pattern (copper 1.3402 x 0.54 mm). */
export const FP0402_CAP = (
  <footprint>
    <smtpad portHints={["1"]} shape="rect" width="0.5mm" height="0.540004mm" pcbX={-0.420116} pcbY={0} />
    <smtpad portHints={["2"]} shape="rect" width="0.5mm" height="0.540004mm" pcbX={0.420116} pcbY={0} />
    <courtyardrect width={COURTYARD.width} height={COURTYARD.height} />
  </footprint>
);
