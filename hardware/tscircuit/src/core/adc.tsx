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

const GND = N.gnd;

export function AdcBoundary() {
  return (
    <>
      {/* 3V3_ADC_A: dedicated low-noise LDO for ADC + driver + bias island only.
          It is never fed from PI_3V3. */}
      <chip
        name="U_ADCLDO"
        footprint="dfn10"
        {...at("adc", "U_ADCLDO")}
        pinLabels={{
          pin1: "OUT", pin2: "SENSE", pin3: "SET", pin4: "ILIM", pin5: "IN",
          pin6: "EN_UV", pin7: "PG", pin8: "GND", pin9: "OUT2", pin10: "PGND",
        }}
        pinAttributes={{ IN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          IN: N.v5sys,
          EN_UV: N.v5sys,
          OUT: N.v3v3adc,
          OUT2: N.v3v3adc,
          SENSE: N.v3v3adc,
          GND: GND,
          PGND: GND,
          ILIM: ".U_ADCLDO > .SET",
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
      <resistor name="R_VCMADC1" resistance="10k" footprint="0402" {...at("adc", "R_VCMADC1")}
        connections={{ pin1: N.v3v3adc, pin2: N.vcmAdc }} />
      <resistor name="R_VCMADC2" resistance="8.06k" footprint="0402" {...at("adc", "R_VCMADC2")}
        connections={{ pin1: N.vcmAdc, pin2: GND }} />

      {/* OPA2835 dual: channel A = signal driver follower, channel B = VCM buffer */}
      <chip
        name="U_DRV"
        footprint="vssop8"
        {...at("adc", "U_DRV")}
        pinLabels={{
          pin1: "OUTA", pin2: "INA_MINUS", pin3: "INA_PLUS", pin4: "V_MINUS",
          pin5: "INB_PLUS", pin6: "INB_MINUS", pin7: "OUTB", pin8: "V_PLUS",
        }}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={{
          INA_MINUS: ".U_DRV > .OUTA",
          INB_MINUS: ".U_DRV > .OUTB",
          V_PLUS: N.v3v3adc,
          V_MINUS: GND,
        }}
      />
      <trace from={N.animp} to=".U_DRV > .INA_PLUS" />
      <trace from={N.vcmAdc} to=".U_DRV > .INB_PLUS" />
      <resistor name="R_ADCIN_P" resistance="10" footprint="0402" {...at("adc", "R_ADCIN_P")}
        connections={{ pin1: ".U_DRV > .OUTA", pin2: N.adcInP }} />
      <resistor name="R_ADCIN_N" resistance="10" footprint="0402" {...at("adc", "R_ADCIN_N")}
        connections={{ pin1: ".U_DRV > .OUTB", pin2: N.adcInN }} />

      {/* LTC1407AIMSE-1: 14-bit, 930 kS/s = 12 x 77.5 kHz. Channel 0 is the receive
          path; channel 1 stays free for the band-pass diagnostic tap. */}
      <chip
        name="U_ADC"
        footprint="msop10"
        {...at("adc", "U_ADC")}
        pinLabels={{
          pin1: "CH0_PLUS", pin2: "CH0_MINUS", pin3: "CH1_PLUS", pin4: "CH1_MINUS",
          pin5: "VREF", pin6: "VDD", pin7: "GND", pin8: "CONV", pin9: "SCK", pin10: "SDO",
        }}
        pinAttributes={{ VDD: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          CH0_PLUS: N.adcInP,
          CH0_MINUS: N.adcInN,
          VREF: N.adcRef,
          VDD: N.v3v3adc,
          GND: GND,
          CONV: N.adcConv,
          SCK: N.adcSck,
          SDO: N.adcSdo,
        }}
      />
      <capacitor name="CADC1" capacitance="10uF" footprint="0805" {...at("adc", "CADC1")}
        connections={{ pin1: N.v3v3adc, pin2: GND }} />
      <capacitor name="CADC2" capacitance="100nF" footprint="0402" {...at("adc", "CADC2")}
        connections={{ pin1: N.v3v3adc, pin2: GND }} />
      <capacitor name="CADC4" capacitance="100nF" footprint="0402" {...at("adc", "CADC4")}
        connections={{ pin1: N.vcmAdc, pin2: GND }} />
      {/* VREF decoupling kept in the protected reference/common-mode island */}
      <capacitor name="CREF1" capacitance="1uF" footprint="0603" {...at("adc", "CREF1")}
        connections={{ pin1: N.adcRef, pin2: GND }} />
      <trace from={N.v3v3adc} to={N.adcRef} />
    </>
  );
}
