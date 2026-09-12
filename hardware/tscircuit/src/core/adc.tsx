/**
 * ADC boundary — LTC1407A-1 @ 930 kS/s with the OPA2835 driver/level-shift stage.
 *
 * docs/11-analog-reference-design.md §5-6: the LTC1407A-1 is a 3 V 14-bit part with
 * a ~-1.25 V .. +1.25 V bipolar differential span, so the 5 V / 2.5 V-centred analog
 * chain is re-biased to a 1.5 V ADC common mode through an explicit AC-coupled
 * driver stage. That driver is a reconstruction addition, not an Engeler original.
 *
 * docs/14: the ADC sits on the analog/digital boundary, LT3042/OPA2835/ADC
 * decoupling stays compact, ADC digital signals leave toward the ECP5, and the
 * reference/common-mode network is protected from digital return currents.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";
import { FP_MSOP10_EP } from "../parts/ic_footprints";
import { pinLabelsOf } from "../parts/pinouts";

const GND = N.gnd;

export function AdcBoundary() {
  return (
    <>
      {/* 3V3_ADC_A: dedicated low-noise LDO for ADC + driver + bias island only.
          It is never fed from PI_3V3.

          LT3042EMSE#PBF is the 10-lead MSOP (MSE) + exposed GND pad, audited in
          ic-pinouts.json. Datasheet-driven wiring: IN1/IN2 and EN/UV to 5V_SYS,
          PGFB tied to IN (power-good and fast-start-up unused), ILIM tied to GND
          (programmable current limit unused — it must NOT be tied to the 100 uA
          SET node), PG left floating (power-good unused), OUT and the Kelvin
          OUTS sense tied to 3V3_ADC_A. */}
      <chip
        name="U_ADCLDO"
        footprint={FP_MSOP10_EP}
        {...at("adc", "U_ADCLDO")}
        pinLabels={pinLabelsOf("U_ADCLDO")}
        pinAttributes={{ IN_1: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          IN_1: N.v5sys,
          IN_2: N.v5sys,
          EN_UV: N.v5sys,
          PGFB: N.v5sys,
          ILIM: GND,
          GND: GND,
          PAD_GND: GND,
          OUTS: N.v3v3adc,
          OUT: N.v3v3adc,
        }}
      />
      <resistor name="RSET_ADC" resistance="33.2k" footprint="0603" {...at("adc", "RSET_ADC")}
        connections={{ pin1: ".U_ADCLDO > .SET", pin2: GND }} />
      <capacitor name="CSET_ADC" capacitance="4.7uF" footprint="0603" {...at("adc", "CSET_ADC")}
        connections={{ pin1: ".U_ADCLDO > .SET", pin2: GND }} />
      <capacitor name="CADC3" capacitance="10uF" footprint="0805" {...at("adc", "CADC3")}
        connections={{ pin1: N.v5sys, pin2: GND }} />

      {/* PGA output -> AC coupling -> 1.5 V ADC common mode -> fast buffer */}
      <capacitor name="C_ADCIN" capacitance="1uF" footprint="0603" {...at("adc", "C_ADCIN")}
        connections={{ pin1: N.pgaOut, pin2: N.animp }} />
      <resistor name="R_VCMADC1" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("adc", "R_VCMADC1")}
        connections={{ pin1: N.v3v3adc, pin2: N.vcmAdc }} />
      <resistor name="R_VCMADC2" resistance="8.06k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C276278"] }} {...at("adc", "R_VCMADC2")}
        connections={{ pin1: N.vcmAdc, pin2: GND }} />

      {/* OPA2835IDGSR dual, 10-pin VSSOP (DGS): channel A = signal driver
          follower, channel B = VCM buffer. Pad identity is audited
          (ic-pinouts.json). PD1/PD2 are active-high shutdown inputs and the data
          sheet states they MUST be driven, so both are tied to V_PLUS. */}
      <chip
        name="U_DRV"
        footprint="vssop10"
        {...at("adc", "U_DRV")}
        pinLabels={pinLabelsOf("U_DRV")}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={{
          VIN_A_MINUS: ".U_DRV > .VOUT_A",
          VIN_B_MINUS: ".U_DRV > .VOUT_B",
          V_PLUS: N.v3v3adc,
          V_MINUS: GND,
          PD_A: N.v3v3adc,
          PD_B: N.v3v3adc,
        }}
      />
      <trace from={N.animp} to=".U_DRV > .VIN_A_PLUS" />
      <trace from={N.vcmAdc} to=".U_DRV > .VIN_B_PLUS" />
      <resistor name="R_ADCIN_P" resistance="10" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25077"] }} {...at("adc", "R_ADCIN_P")}
        connections={{ pin1: ".U_DRV > .VOUT_A", pin2: N.adcInP }} />
      <resistor name="R_ADCIN_N" resistance="10" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25077"] }} {...at("adc", "R_ADCIN_N")}
        connections={{ pin1: ".U_DRV > .VOUT_B", pin2: N.adcInN }} />

      {/* LTC1407AIMSE-1: 14-bit, 930 kS/s = 12 x 77.5 kHz, 10-lead MSOP (MSE)
          plus the exposed GND pad. Pad identity is audited in ic-pinouts.json:
          1 CH0+, 2 CH0-, 3 VREF, 4 CH1+, 5 CH1-, 6 GND, 7 VDD, 8 SDO, 9 SCK,
          10 CONV, 11 exposed pad -> GND. Channel 0 is the receive path;
          channel 1 stays free for the band-pass diagnostic tap. */}
      <chip
        name="U_ADC"
        footprint={FP_MSOP10_EP}
        {...at("adc", "U_ADC")}
        pinLabels={pinLabelsOf("U_ADC")}
        pinAttributes={{ VDD: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          CH0_PLUS: N.adcInP,
          CH0_MINUS: N.adcInN,
          VREF: N.adcRef,
          VDD: N.v3v3adc,
          GND: GND,
          PAD_GND: GND,
          CONV: N.adcConv,
          SCK: N.adcSck,
          SDO: N.adcSdo,
        }}
      />
      <capacitor name="CADC1" capacitance="10uF" footprint="0805" {...at("adc", "CADC1")}
        connections={{ pin1: N.v3v3adc, pin2: GND }} />
      <capacitor name="CADC2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("adc", "CADC2")}
        connections={{ pin1: N.v3v3adc, pin2: GND }} />
      <capacitor name="CADC4" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("adc", "CADC4")}
        connections={{ pin1: N.vcmAdc, pin2: GND }} />
      {/* VREF decoupling kept in the protected reference/common-mode island */}
      <capacitor name="CREF1" capacitance="1uF" footprint="0603" {...at("adc", "CREF1")}
        connections={{ pin1: N.adcRef, pin2: GND }} />
      <trace from={N.v3v3adc} to={N.adcRef} />
    </>
  );
}
