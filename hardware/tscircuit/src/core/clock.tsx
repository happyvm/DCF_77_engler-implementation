/**
 * 25 MHz reference clock: SiT5356 TCXO on its own TPS7A2033 rail.
 *
 * docs/14 "Clock": SiT5356 physically separated from the ferrite/first analog
 * stage, short direct route to ECP5 C9 (PT47B/GR_PCLK1_1, bank 1), no long clock
 * test stub, clock return current stays in the digital region.
 * docs/19 §3V3_CLK: TPS7A2033PDQNR, CIN/COUT 2.2 uF, 100 nF directly at the TCXO.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_CAP } from "../parts/footprints";

const GND = N.gnd;

export function ReferenceClock() {
  return (
    <>
      {/* 3V3_CLK: dedicated to the fixed 25 MHz TCXO, sourced from 5V_SYS. */}
      <chip
        name="U_CLKLDO"
        footprint="sot23-5"
        {...at("tcxo", "U_CLKLDO")}
        pinLabels={{ pin1: "IN", pin2: "GND", pin3: "EN", pin4: "NC", pin5: "OUT" }}
        pinAttributes={{ IN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ IN: N.v5sys, EN: N.v5sys, OUT: N.v3v3clk, GND: GND }}
      />
      <capacitor name="CCLK_LDO_IN" capacitance="2.2uF" footprint="0603" {...at("tcxo", "CCLK_LDO_IN")}
        connections={{ pin1: N.v5sys, pin2: GND }} />
      <capacitor name="CCLK_LDO_OUT" capacitance="2.2uF" footprint="0603" {...at("tcxo", "CCLK_LDO_OUT")}
        connections={{ pin1: N.v3v3clk, pin2: GND }} />

      {/* SiT5356AI-FQ-33E0-25.000000, 25 MHz LVCMOS, ±100 ppb, 3.3 V, 4-pad. */}
      <chip
        name="U_CLK"
        footprint="dfn4"
        {...at("tcxo", "U_CLK")}
        pinLabels={{ pin1: "OE", pin2: "GND", pin3: "OUT", pin4: "VDD" }}
        pinAttributes={{ VDD: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ VDD: N.v3v3clk, GND: GND, OUT: N.clk25m, OE: N.v3v3clk }}
      />
      <capacitor name="CCLK1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("tcxo", "CCLK1")}
        connections={{ pin1: N.v3v3clk, pin2: GND }} />
      {/* CLK_25M terminates on ECP5 ball C9 = pin157 of the audited BG256 pin plan. */}
    </>
  );
}
