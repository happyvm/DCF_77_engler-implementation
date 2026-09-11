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

const GND = N.gnd;

export function PpsInterface() {
  return (
    <>
      {/* Dedicated PPS output buffer, 3V3_D domain. */}
      <chip
        name="U_PPS"
        footprint="sot23-5"
        {...lockedAt("U_PPS")}
        pinLabels={{ pin1: "A", pin2: "GND", pin3: "OE", pin4: "NC", pin5: "VCC" }}
        pinAttributes={{ VCC: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ A: N.ppsRef, OE: GND, VCC: N.v3v3d, GND: GND }}
      />

      <resistor name="RPS1" resistance="33" footprint="0402" {...at("host_debug", "RPS1")}
        connections={{ pin1: ".U_PPS > .A", pin2: N.ppsOut }} />

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
      {/* PPS_REF is also observable directly on the locked buffer input. */}
      <trace from={N.ppsRef} to=".U_PPS > .A" />
    </>
  );
}
