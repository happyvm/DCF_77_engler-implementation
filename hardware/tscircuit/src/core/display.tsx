/**
 * Local 20x2 transflective LCD (NHD-C0220BIZ-FSW-FBW-3V3M, ST7036, I2C).
 *
 * docs/24-lcd-display.md: VDD = 3V3_D / PI_3V3, 100 nF + 1 uF local, slow I2C
 * (~100 kHz), LCD logic on 3V3_D, backlight from 5V_SYS through fixed current
 * limiting and a small N-MOSFET, backlight OFF in precision RF mode.
 * The module is a mechanical constraint: 75.7 x 27.1 mm outline, wider than the
 * HAT+ board, so the locked position intentionally overhangs the edge.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";

const GND = N.gnd;

export function LocalDisplay() {
  return (
    <>
      {/* Locked mechanical position; the pad row is the module's interface edge. */}
      <chip
        name="DS1"
        {...at("lcd", "DS1")}
        pinLabels={{
          pin1: "VDD", pin2: "GND", pin3: "SDA", pin4: "SCL",
          pin5: "RST", pin6: "LED_A", pin7: "LED_K",
        }}
        pinAttributes={{ VDD: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          VDD: N.v3v3d,
          GND: GND,
          SDA: N.lcdSda,
          SCL: N.lcdScl,
          RST: N.lcdRstN,
          LED_A: N.lcdBlA,
          LED_K: N.lcdBlK,
        }}
      >
        <footprint>
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={-6.0} pcbY={0} portHints={["pin1"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={-4.0} pcbY={0} portHints={["pin2"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={-2.0} pcbY={0} portHints={["pin3"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={0.0} pcbY={0} portHints={["pin4"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={2.0} pcbY={0} portHints={["pin5"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={4.0} pcbY={0} portHints={["pin6"]} />
          <smtpad shape="rect" width="1.4mm" height="1.4mm" pcbX={6.0} pcbY={0} portHints={["pin7"]} />
        </footprint>
      </chip>

      <capacitor name="CBL1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("lcd", "CBL1")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="CBL2" capacitance="1uF" footprint="0603" {...at("lcd", "CBL2")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />

      {/* I2C pull-ups on the ECP5-side bank-3 bus */}
      <resistor name="RLCD_SCL" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("lcd", "RLCD_SCL")}
        connections={{ pin1: N.v3v3d, pin2: N.lcdScl }} />
      <resistor name="RLCD_SDA" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("lcd", "RLCD_SDA")}
        connections={{ pin1: N.v3v3d, pin2: N.lcdSda }} />

      {/* Backlight: fixed current limiting from 5V_SYS, switched by a small N-MOSFET.
          The ECP5 drives the gate with a static ON/OFF signal, never PWM.

          Final Rev.0 values (docs/24: VLED ~3.0 V typ, Iled ~30 mA typ, 35 mA max):
            target ~28 mA nominal, hard ceiling <= 35 mA over PI_5V 4.75..5.25 V
            and Vf 2.9..3.2 V with Vds(on) ~0.15 V at 30 mA
              RBL1 = (5.00 - 3.00 - 0.15) / 0.028 = 66.1 ohm -> 68 ohm (E24)
            worst case  = (5.25 - 2.90 - 0.05) / 68 = 33.8 mA  (<= 35 mA)
            dimmest     = (4.75 - 3.20 - 0.15) / 68 = 20.6 mA
            RBL1 power  = 33.8 mA^2 * 68 = 78 mW -> 0805 (125 mW) with margin.
          A shorted LED would dissipate ~0.4 W in RBL1; the thick-film part fails
          open, i.e. fail-safe with the backlight off, which is acceptable here.

          LCD_BLQ is a logic-level N-MOSFET (BSS138, Vgs(th) <= 1.5 V) so the 3V3_D
          gate fully enhances it. RBL2 is the series gate resistor; RBL3 holds the
          gate low so the backlight stays OFF while the ECP5 is unconfigured, in
          reset, or tri-stated — OFF is the safe precision-RF state. */}
      <resistor name="RBL1" resistance="68" footprint="0805" {...at("lcd", "RBL1")}
        connections={{ pin1: N.v5sys, pin2: N.lcdBlA }} />
      <resistor name="RBL2" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("lcd", "RBL2")}
        connections={{ pin1: N.lcdBlEn, pin2: N.lcdBlGate }} />
      <resistor name="RBL3" resistance="100k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25741"] }} {...at("lcd", "RBL3")}
        connections={{ pin1: N.lcdBlGate, pin2: GND }} />
      <chip
        name="LCD_BLQ"
        footprint="sot23"
        {...at("lcd", "LCD_BLQ")}
        pinLabels={{ pin1: "GATE", pin2: "SOURCE", pin3: "DRAIN" }}
        connections={{ GATE: N.lcdBlGate, SOURCE: GND, DRAIN: N.lcdBlK }}
      />
    </>
  );
}
