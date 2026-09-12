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
import { FP_TCXO_5032_10, FP_X2SON4_EP } from "../parts/ic_footprints";
import { pinLabelsOf } from "../parts/pinouts";

const GND = N.gnd;

export function ReferenceClock() {
  return (
    <>
      {/* 3V3_CLK: dedicated to the fixed 25 MHz TCXO, sourced from 5V_SYS.

          TPS7A2033PDQNR is the 4-pin X2SON (DQN) option, not the SOT-23-5:
          audited map 1 OUT, 2 GND, 3 EN, 4 IN, 5 thermal pad -> GND. */}
      <chip
        name="U_CLKLDO"
        footprint={FP_X2SON4_EP}
        {...at("tcxo", "U_CLKLDO")}
        pinLabels={pinLabelsOf("U_CLKLDO")}
        pinAttributes={{ IN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ IN: N.v5sys, EN: N.v5sys, OUT: N.v3v3clk, GND: GND, THERMAL_PAD: GND }}
      />
      <capacitor name="CCLK_LDO_IN" capacitance="2.2uF" footprint="0603" {...at("tcxo", "CCLK_LDO_IN")}
        connections={{ pin1: N.v5sys, pin2: GND }} />
      <capacitor name="CCLK_LDO_OUT" capacitance="2.2uF" footprint="0603" {...at("tcxo", "CCLK_LDO_OUT")}
        connections={{ pin1: N.v3v3clk, pin2: GND }} />

      {/* SiT5356AI-FQ-33E0-25.000000, 25 MHz LVCMOS, ±100 ppb, 3.3 V.
          Real package is a 10-pad 5.0 x 3.2 mm 10L CQFN (audited map):
          1 OE, 2 SCL/NC, 3 NC, 4 GND, 5 A0/NC, 6 CLK, 7 NC, 8 NC, 9 VDD,
          10 SDA/NC. OE is tied high for an always-enabled output and the unused
          NC pads are grounded per the datasheet layout guideline. */}
      <chip
        name="U_CLK"
        footprint={FP_TCXO_5032_10}
        {...at("tcxo", "U_CLK")}
        pinLabels={pinLabelsOf("U_CLK")}
        pinAttributes={{ VDD: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          VDD: N.v3v3clk,
          GND: GND,
          CLK: N.clk25m,
          OE: N.v3v3clk,
          SCL_NC: GND,
          NC_3: GND,
          A0_NC: GND,
          NC_7: GND,
          NC_8: GND,
          SDA_NC: GND,
        }}
      />
      <capacitor name="CCLK1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("tcxo", "CCLK1")}
        connections={{ pin1: N.v3v3clk, pin2: GND }} />
      {/* CLK_25M terminates on ECP5 ball C9 = pin157 of the audited BG256 pin plan. */}
    </>
  );
}
