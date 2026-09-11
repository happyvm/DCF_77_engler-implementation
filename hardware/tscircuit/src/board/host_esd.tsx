/**
 * HAT+/test-interface ESD protection (Rev.0 freeze).
 *
 * docs/14 "Locked before Quilter" makes the external PPS/test interface a locked
 * object, and docs/references.md listed "any HAT-side ESD/protection device not
 * yet frozen" as an open sourcing item. This file is that freeze.
 *
 * Rev.0 decision:
 *
 *   J3 (external 4-pin PPS/test header) IS user-reachable, so it gets real ESD
 *   clamps: one single-line bidirectional TVS per exposed signal pin
 *   (PPS_OUT, 3V3_D_REF), in SOD-882 (1.0 x 0.6 mm body, e.g. PESD5V0S1US-typ,
 *   IEC 61000-4-2 +-8 kV contact). SOD-882 keeps the clamp inside the space the
 *   packed host_debug region can actually afford; a SOT-23-6 2-line array would
 *   not fit without moving the floorplan.
 *
 *   J1 (the Raspberry Pi HAT+ 40-pin header) is a board-to-board interface that
 *   is mated inside the assembly. Every Pi-facing line already has a defined
 *   idle state and the fast ones carry 33 ohm source-series damping
 *   (src/host/rpi_spi.tsx), so Rev.0 deliberately adds NO ESD device there:
 *   4-line arrays on 9 signal pins would add stray capacitance and a second
 *   return path on the host SPI/UART nets for no justified risk reduction.
 *   Revisit this if J1 ever becomes user-accessible (e.g. a front-panel or bench
 *   cable variant): the SPI/UART/IRQ/RESET group then becomes ESD-exposed.
 *
 * The 1V1_CORE buck and all analog rails are untouched here; this file only
 * protects the digital/test interface in the host_debug region.
 */
import { N } from "../parts/nets";
import { at } from "../parts";

const GND = N.gnd;

export function HostEsdProtection() {
  return (
    <>
      {/* D_ESD_PPS: clamp on the external PPS output line. */}
      <chip
        name="D_ESD_PPS"
        footprint="sod882"
        {...at("host_debug", "D_ESD_PPS")}
        pinLabels={{ pin1: "LINE", pin2: "GND" }}
        connections={{ LINE: N.ppsOut, GND: GND }}
      />
      {/* D_ESD_REF: clamp on the 3V3_D reference pin of the test header. */}
      <chip
        name="D_ESD_REF"
        footprint="sod882"
        {...at("host_debug", "D_ESD_REF")}
        pinLabels={{ pin1: "LINE", pin2: "GND" }}
        connections={{ LINE: N.v3v3d, GND: GND }}
      />
    </>
  );
}
