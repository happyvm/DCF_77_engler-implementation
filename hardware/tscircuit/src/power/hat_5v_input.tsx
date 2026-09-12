/**
 * HAT+ 5 V input switch.
 *
 * docs/19 §"HAT+ input switch", docs/26 and docs/28 §6:
 *   PI_5V -> VIN/VBIAS, PI_3V3 -> ON, ON -> 100 kOhm -> GND,
 *   CT -> 1.0 nF (>=30 V) -> GND, VOUT -> 5V_SYS.
 *
 * The N variant is used without a quick-output-discharge resistor. When PI_3V3
 * disappears in HAT+ STANDBY the switch turns off and every locally generated
 * receiver rail collapses, so no HAT GPIO can back-power the Pi.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES } from "../parts/footprints";
import { pinLabelsOf } from "../parts/pinouts";

const GND = N.gnd;

export function Hat5vInput() {
  return (
    <>
      {/* TPS22975NDSGR is an 8-pin WSON (DSG) load switch with an exposed GND pad,
          not a 6-pin SOT-23: VIN is pins 1+2, VOUT is pins 7+8, CT is pin 6 and
          GND is pin 5. Pad identity is audited (ic-pinouts.json). */}
      <chip
        name="U_SW"
        footprint="wson8"
        {...at("power_1v1", "U_SW")}
        pinLabels={pinLabelsOf("U_SW")}
        pinAttributes={{ VIN_1: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          VIN_1: N.pi5v,
          VIN_2: N.pi5v,
          VBIAS: N.pi5v,
          ON: N.pi3v3,
          VOUT_1: N.v5sys,
          VOUT_2: N.v5sys,
          GND: GND,
          THERMAL_PAD: GND,
        }}
      />
      <resistor name="RON_PD" resistance="100k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25741"] }} {...at("power_1v1", "RON_PD")}
        connections={{ pin1: N.pi3v3, pin2: GND }} />
      <capacitor name="CT_SW" capacitance="1nF" footprint="0603" {...at("power_1v1", "CT_SW")}
        connections={{ pin1: ".U_SW > .CT", pin2: GND }} />
    </>
  );
}
