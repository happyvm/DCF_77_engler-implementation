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

const GND = N.gnd;

export function Hat5vInput() {
  return (
    <>
      <chip
        name="U_SW"
        footprint="sot23-6"
        {...at("power_1v1", "U_SW")}
        pinLabels={{ pin1: "VIN", pin2: "GND", pin3: "ON", pin4: "VBIAS", pin5: "CT", pin6: "VOUT" }}
        pinAttributes={{ VIN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          VIN: N.pi5v,
          VBIAS: N.pi5v,
          ON: N.pi3v3,
          VOUT: N.v5sys,
          GND: GND,
        }}
      />
      <resistor name="RON_PD" resistance="100k" footprint="0402" {...at("power_1v1", "RON_PD")}
        connections={{ pin1: N.pi3v3, pin2: GND }} />
      <capacitor name="CT_SW" capacitance="1nF" footprint="0603" {...at("power_1v1", "CT_SW")}
        connections={{ pin1: ".U_SW > .CT", pin2: GND }} />
    </>
  );
}
