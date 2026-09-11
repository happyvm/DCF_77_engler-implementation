/**
 * Analog front end — Rev.0 signal order.
 *
 *   TDK B82453C0275A000 (X winding, Y/Z open)
 *     -> OPA810 high-impedance follower
 *     -> LTC1562 8th-order BPF 77.5 kHz / 7.75 kHz / gain 10
 *     -> 1 uF AC coupling -> LTC6912-1 PGA (channel A)
 *
 * Sources: docs/20-antenna-input.md, docs/21-ltc1562-fixed-filter.md,
 * docs/22-ltc6912-pga.md and hardware/tscircuit/README.md.
 *
 * RECONSTRUCTION NOTE
 * -------------------
 * The LTC1562 internal section pinout and the LTC6912 GN-16 pinout are not
 * reproduced in this repository. The nets below are the documented signal
 * topology; the pad-number-to-pin-name mapping of those two ICs must be
 * confirmed against the ADI datasheets before the schematic is frozen.
 * (hardware/tscircuit/README.md -> "Remaining schematic-freeze work".)
 */
import { N } from "../parts/nets";
import { at, lockedAt } from "../parts";

const GND = N.gnd;

// ---------------------------------------------------------------------------
// antenna + fixed tuning network + OPA810 buffer
// ---------------------------------------------------------------------------
export function AntennaInputCluster() {
  return (
    <>
      {/* TDK B82453C0275A000, 12.5 x 11.5 x 3.6 mm. X winding only; Y and Z are
          left open (never shorted) so they do not magnetically load the X axis. */}
      <chip
        name="ANT1"
        {...lockedAt("ANT1")}
        pinLabels={{ pin1: "X1", pin2: "X2", pin3: "Y1", pin4: "Y2", pin5: "Z1", pin6: "Z2" }}
        connections={{
          X1: N.antIn,
          X2: N.vcmAfe,
          // Y1/Y2/Z1/Z2 stay open in Rev.0.
        }}
      >
        <footprint>
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={-5.75} pcbY={-4.0} portHints={["pin1"]} />
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={5.75} pcbY={-4.0} portHints={["pin2"]} />
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={-5.75} pcbY={0.0} portHints={["pin3"]} />
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={5.75} pcbY={0.0} portHints={["pin4"]} />
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={-5.75} pcbY={4.0} portHints={["pin5"]} />
          <smtpad shape="rect" width="3mm" height="2.2mm" pcbX={5.75} pcbY={4.0} portHints={["pin6"]} />
        </footprint>
      </chip>

      {/* fixed resonance network: CANT1 || CANT2 || RANT between ANT_IN and the
          low-AC-impedance VCM_AFE node. No trimmer, no per-board selection. */}
      <capacitor name="CANT1" capacitance="560pF" footprint="0603" {...at("ferrite_afe", "CANT1")}
        connections={{ pin1: N.antIn, pin2: N.vcmAfe }} />
      <capacitor name="CANT2" capacitance="22pF" footprint="0603" {...at("ferrite_afe", "CANT2")}
        connections={{ pin1: N.antIn, pin2: N.vcmAfe }} />
      <resistor name="RANT" resistance="330k" footprint="0603" {...at("ferrite_afe", "RANT")}
        connections={{ pin1: N.antIn, pin2: N.vcmAfe }} />

      {/* quiet 2.5 V analog bias from 5V_AFE */}
      <resistor name="R1" resistance="10k" footprint="0603" {...at("ferrite_afe", "R1")}
        connections={{ pin1: N.v5afe, pin2: N.vcmAfe }} />
      <resistor name="R2" resistance="10k" footprint="0603" {...at("ferrite_afe", "R2")}
        connections={{ pin1: N.vcmAfe, pin2: GND }} />
      <capacitor name="CVCM1" capacitance="10uF" footprint="0805" {...at("ferrite_afe", "CVCM1")}
        connections={{ pin1: N.vcmAfe, pin2: GND }} />
      <capacitor name="CVCM2" capacitance="1uF" footprint="0603" {...at("ferrite_afe", "CVCM2")}
        connections={{ pin1: N.vcmAfe, pin2: GND }} />
      <capacitor name="CVCM3" capacitance="100nF" footprint="0402" {...at("ferrite_afe", "CVCM3")}
        connections={{ pin1: N.vcmAfe, pin2: GND }} />

      {/* OPA810IDBVR voltage follower, 5V_AFE, single supply */}
      <chip
        name="U_BUF"
        footprint="sot23-5"
        {...lockedAt("U_BUF")}
        pinLabels={{ pin1: "OUT", pin2: "V_MINUS", pin3: "IN_PLUS", pin4: "IN_MINUS", pin5: "V_PLUS" }}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={{
          OUT: N.afeOut,
          IN_MINUS: N.afeOut,
          IN_PLUS: N.antIn,
          V_PLUS: N.v5afe,
          V_MINUS: GND,
        }}
      />

      {/* DC interface into the filter: the coupling capacitor is not a tuning element. */}
      <capacitor name="C_BUF" capacitance="1uF" footprint="0603" {...lockedAt("C_BUF")}
        connections={{ pin1: N.afeOut, pin2: N.bpfIn }} />
    </>
  );
}

// ---------------------------------------------------------------------------
// LTC1562 8th-order band-pass, fixed 77.5 kHz
// ---------------------------------------------------------------------------
export function BandPassFilter() {
  const connections = {
    V_PLUS: N.v5afe,
    V_MINUS: GND,
    SHDN: GND, // ADI requires logic low referenced to V- in single-supply mode
    IN1: N.bpfIn,
  };
  return (
    <>
      <chip
        name="U_BPF"
        footprint="ssop20"
        {...at("filter", "U_BPF")}
        pinLabels={{
          pin1: "V_PLUS", pin2: "V_MINUS", pin3: "AGND", pin4: "SHDN",
          pin5: "IN1", pin6: "INV1", pin7: "OUT1",
          pin8: "IN2", pin9: "INV2", pin10: "OUT2",
          pin11: "IN3", pin12: "INV3", pin13: "OUT3",
          pin14: "IN4", pin15: "INV4", pin16: "OUT4",
          pin17: "R21_NODE", pin18: "R22_NODE", pin19: "R23_NODE", pin20: "R24_NODE",
        }}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={connections}
      />
      {/* programming resistors — 0.1% thin film, fixed values, no trimmer */}
      <resistor name="RIN1" resistance="4.79k" footprint="0603" {...at("filter", "RIN1")}
        connections={{ pin1: N.bpfIn, pin2: ".U_BPF > .IN1" }} />
      <resistor name="RQ1" resistance="47.9k" footprint="0603" {...at("filter", "RQ1")}
        connections={{ pin1: ".U_BPF > .IN1", pin2: ".U_BPF > .INV1" }} />
      <resistor name="R21" resistance="12.8k" footprint="0603" {...at("filter", "R21")}
        connections={{ pin1: ".U_BPF > .INV1", pin2: ".U_BPF > .OUT1" }} />
      <resistor name="RIN2" resistance="47.9k" footprint="0603" {...at("filter", "RIN2")}
        connections={{ pin1: ".U_BPF > .OUT1", pin2: ".U_BPF > .IN2" }} />
      <resistor name="RQ2" resistance="47.9k" footprint="0603" {...at("filter", "RQ2")}
        connections={{ pin1: ".U_BPF > .IN2", pin2: ".U_BPF > .INV2" }} />
      <resistor name="R22" resistance="12.8k" footprint="0603" {...at("filter", "R22")}
        connections={{ pin1: ".U_BPF > .INV2", pin2: ".U_BPF > .OUT2" }} />
      <resistor name="RIN3" resistance="47.9k" footprint="0603" {...at("filter", "RIN3")}
        connections={{ pin1: ".U_BPF > .OUT2", pin2: ".U_BPF > .IN3" }} />
      <resistor name="RQ3" resistance="47.9k" footprint="0603" {...at("filter", "RQ3")}
        connections={{ pin1: ".U_BPF > .IN3", pin2: ".U_BPF > .INV3" }} />
      <resistor name="R23" resistance="12.8k" footprint="0603" {...at("filter", "R23")}
        connections={{ pin1: ".U_BPF > .INV3", pin2: ".U_BPF > .OUT3" }} />
      <resistor name="RIN4" resistance="47.9k" footprint="0603" {...at("filter", "RIN4")}
        connections={{ pin1: ".U_BPF > .OUT3", pin2: ".U_BPF > .IN4" }} />
      <resistor name="RQ4" resistance="47.9k" footprint="0603" {...at("filter", "RQ4")}
        connections={{ pin1: ".U_BPF > .IN4", pin2: ".U_BPF > .INV4" }} />
      <resistor name="R24" resistance="12.8k" footprint="0603" {...at("filter", "R24")}
        connections={{ pin1: ".U_BPF > .INV4", pin2: ".U_BPF > .OUT4" }} />
      {/* AGND is bypassed locally with a short return; it is not a general-purpose source. */}
      <capacitor name="CBPF1" capacitance="1uF" footprint="0603" {...at("filter", "CBPF1")}
        connections={{ pin1: ".U_BPF > .AGND", pin2: GND }} />
      <capacitor name="CBPF2" capacitance="100nF" footprint="0402" {...at("filter", "CBPF2")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      {/* filter output node */}
      <trace from=".U_BPF > .OUT4" to={N.bpfOut} />
    </>
  );
}

// ---------------------------------------------------------------------------
// LTC6912-1 programmable gain stage (channel A = receive path)
// ---------------------------------------------------------------------------
export function ProgrammableGain() {
  return (
    <>
      <chip
        name="U_PGA"
        footprint="ssop16"
        {...at("pga", "U_PGA")}
        pinLabels={{
          pin1: "INA", pin2: "INB", pin3: "AGND", pin4: "V_MINUS",
          pin5: "V_PLUS", pin6: "SHDN", pin7: "DGND", pin8: "DAT",
          pin9: "CLK", pin10: "CS_LD", pin11: "DOUT",
          pin12: "OUTA", pin13: "OUTB", pin14: "NC1", pin15: "NC2", pin16: "NC3",
        }}
        pinAttributes={{ V_PLUS: { requiresPower: true }, DGND: { requiresGround: true } }}
        connections={{
          INA: N.pgaIn,
          OUTA: N.pgaOut,
          V_PLUS: N.v5afe,
          V_MINUS: GND,
          DGND: GND,
          // DOUT is not used in Rev.0 and stays unconnected (5 V logic output).
        }}
      />
      {/* explicit AC coupling between the two ICs: their DC offsets must not be
          multiplied by the high PGA gains. */}
      <capacitor name="C_PGAIN" capacitance="1uF" footprint="0603" {...at("pga", "C_PGAIN")}
        connections={{ pin1: N.bpfOut, pin2: N.pgaIn }} />
      <resistor name="R_PGABIAS" resistance="1M" footprint="0603" {...at("pga", "R_PGABIAS")}
        connections={{ pin1: N.pgaIn, pin2: ".U_PGA > .AGND" }} />
      <capacitor name="CPGA1" capacitance="1uF" footprint="0603" {...at("pga", "CPGA1")}
        connections={{ pin1: ".U_PGA > .AGND", pin2: GND }} />
      <capacitor name="CPGA2" capacitance="100nF" footprint="0402" {...at("pga", "CPGA2")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      {/* PGA powers up enabled whenever 5V_AFE is present */}
      <resistor name="RPGA_SHDN" resistance="100k" footprint="0402" {...at("pga", "RPGA_SHDN")}
        connections={{ pin1: ".U_PGA > .SHDN", pin2: GND }} />
      {/* ~100 ohm source-series resistors near the ECP5 on the low-rate SPI bus */}
      <resistor name="RS_PGA_SCK" resistance="100" footprint="0402" {...at("pga", "RS_PGA_SCK")}
        connections={{ pin1: N.pgaSck, pin2: N.pgaSckF }} />
      <resistor name="RS_PGA_MOSI" resistance="100" footprint="0402" {...at("pga", "RS_PGA_MOSI")}
        connections={{ pin1: N.pgaMosi, pin2: N.pgaMosiF }} />
      <resistor name="RS_PGA_CS" resistance="100" footprint="0402" {...at("pga", "RS_PGA_CS")}
        connections={{ pin1: N.pgaCsN, pin2: N.pgaCsF }} />
      <trace from=".RS_PGA_SCK > .pin2" to=".U_PGA > .CLK" />
      <trace from=".RS_PGA_MOSI > .pin2" to=".U_PGA > .DAT" />
      <trace from=".RS_PGA_CS > .pin2" to=".U_PGA > .CS_LD" />
    </>
  );
}
