/**
 * Audited IC pin identity — the schematic-freeze counterpart of the ECP5 ball plan.
 *
 * `ic-pinouts.json` is the machine-readable source of truth for the pad-number to
 * pin-name mapping of the non-FPGA ICs. It is consumed here so the TSX cannot
 * diverge from the audited identity, and gated by `scripts/verify-ic-pinouts.ts`.
 *
 * Do not inline a pin label map in a component file: an invented pin name silently
 * moves a net to the wrong physical pad, which is exactly the failure mode this
 * plan exists to prevent.
 */
import pinouts from "../../ic-pinouts.json";

export type PartPinout = {
  ref: string;
  opn: string;
  device: string;
  package: string;
  pins: Record<string, string>;
  pin_alias?: Record<string, string>;
  notes?: string[];
  source: {
    document: string;
    vendor: string;
    url: string;
    mirror?: string;
    retrieved: string;
    retrieved_artifact_sha256: string;
    evidence?: string;
  };
};

export const IC_PINOUTS = pinouts.parts as unknown as Record<string, PartPinout>;

export const IC_PINOUT_STATUS = pinouts.status as {
  audited: string[];
  pending: string[];
  pending_scope: string;
};

/**
 * Audited `pinN -> pin name` map for a part.
 *
 * Throws when the part was never audited: wiring an unverified package would put
 * nets on invented pads, so it is a build-time error rather than a warning.
 */
export function pinLabelsOf(ref: string): Record<string, string> {
  const p = IC_PINOUTS[ref];
  if (!p) {
    throw new Error(
      `"${ref}" has no audited pinout in hardware/tscircuit/ic-pinouts.json — ` +
        `verify it against the manufacturer pinout before wiring it.`,
    );
  }
  return p.pins;
}

/** True when the part's pad identity was cross-checked against a manufacturer pinout. */
export const isAudited = (ref: string): boolean => IC_PINOUT_STATUS.audited.includes(ref);
