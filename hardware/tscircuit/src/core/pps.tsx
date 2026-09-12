/**
 * External PPS / test interface.
 *
 * docs/27 §6: PPS_REF (ECP5 ball R12, bank 3) feeds the dedicated external output
 * path; a separate internal copy (ball A11) reaches the Raspberry Pi GPIO.
 * docs/14 "Locked before Quilter": the external PPS connector / test interface is
 * a locked object at the board edge, away from the ferrite.
 */
import { N } from "../parts/nets";
import { at, lockedAt } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";
import { pinLabelsOf } from "../parts/pinouts";

const GND = N.gnd;

export function PpsInterface() {
  return (
    <>
      {/* Dedicated PPS output buffer, 3V3_D domain. Frozen MPN SN74LVC1G125DBVR
          (audited in ic-pinouts.json): 1 OE, 2 A, 3 GND, 4 Y, 5 VCC.
          OE is active low and tied to GND -> permanently enabled; the ECP5
          PPS_REF drives A and Y drives PPS_OUT through RPS1. */}
      <chip
        name="U_PPS"
        footprint="sot23-5"
        {...lockedAt("U_PPS")}
        pinLabels={pinLabelsOf("U_PPS")}
        pinAttributes={{ VCC: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ A: N.ppsRef, OE: GND, VCC: N.v3v3d, GND: GND }}
      />
      <capacitor name="CUPS1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("host_debug", "CUPS1")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />

      <resistor name="RPS1" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RPS1")}
        connections={{ pin1: ".U_PPS > .Y", pin2: N.ppsOut }} />

      {/* External PPS / test interface: PPS out, 3V3_D reference, two grounds.
          ESD-clamped by D_ESD_PPS (src/board/host_esd.tsx). */}
      <chip
        name="J3"
        footprint="pinheader4"
        {...at("host_debug", "J3")}
        pinLabels={{ pin1: "PPS_OUT", pin2: "3V3_D_REF", pin3: "GND", pin4: "GND" }}
        pinAttributes={{ "3V3_D_REF": { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ PPS_OUT: N.ppsOut, "3V3_D_REF": N.v3v3d, GND: GND, pin4: GND }}
      />
    </>
  );
}
