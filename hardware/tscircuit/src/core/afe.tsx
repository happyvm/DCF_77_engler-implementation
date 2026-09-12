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
 * PINOUT STATUS
 * -------------
 * U_BPF (LTC1562IG#PBF, 20-lead SSOP) and U_PGA (LTC6912IGN-1#PBF, 16-lead
 * narrow SSOP) now take their pad-number-to-pin-name map from
 * `hardware/tscircuit/ic-pinouts.json`, which is derived from the manufacturer
 * data sheets (1562fa, 6912fa) and gated by `scripts/verify-ic-pinouts.ts`.
 * Before that audit this file carried an invented map: e.g. the LTC1562 was
 * wired with "IN1/INV1/OUT1" section pins and the LTC6912 with a pinout that
 * matched neither its GN-16 nor its DFN-12 package. Both are wiring defects,
 * not cosmetic ones, and both are now closed.
 *
 * The remaining ICs in `ic-pinouts.json -> status.pending` keep functional net
 * names on their footprints and are still awaiting the same cross-check.
 */
import { N } from "../parts/nets";
import { at, lockedAt } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";
import { pinLabelsOf } from "../parts/pinouts";

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
      <capacitor name="CVCM3" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ferrite_afe", "CVCM3")}
        connections={{ pin1: N.vcmAfe, pin2: GND }} />

      {/* OPA810IDBVR voltage follower, 5V_AFE, single supply. Pad identity is audited
          (ic-pinouts.json): DBV-5 = 1 VO, 2 VS-, 3 VIN+, 4 VIN-, 5 VS+. */}
      <chip
        name="U_BUF"
        footprint="sot23-5"
        {...lockedAt("U_BUF")}
        pinLabels={pinLabelsOf("U_BUF")}
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
  // LTC1562 Figure 3 / Figure 6a band-pass wiring, 8th order = four cascaded
  // 2nd-order sections in the B -> A -> C -> D order of the ADI reference
  // application (docs/21). Each section is a 3-terminal block:
  //
  //   <source> --RINx--> INVx --+-- RQx --> V1x   band-pass output
  //                             +-- R2x --> V2x   low-pass output
  //
  // V1x carries the cascaded band-pass signal; V2x is only used to close the R2x
  // feedback path. Pins 4, 7, 14 and 17 (SUB) are substrate/shield connections
  // internally tied to V- and must be soldered to the same point as pin 16.
  const connections = {
    V_PLUS: N.v5afe,
    V_MINUS: GND,
    SUB_4: GND,
    SUB_7: GND,
    SUB_14: GND,
    SUB_17: GND,
    SHDN: GND, // ADI requires logic low referenced to V- in single-supply mode
  };
  return (
    <>
      <chip
        name="U_BPF"
        footprint="ssop20"
        {...at("filter", "U_BPF")}
        pinLabels={pinLabelsOf("U_BPF")}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={connections}
      />
      {/* programming resistors — 0.1% thin film, fixed values, no trimmer.
          Section B is the input section (RIN1 = 4.79k gives the gain-10 band-pass
          peak against RQ1), sections A, C, D are unity-gain band-pass stages. */}
      <resistor name="RIN1" resistance="4.79k" footprint="0603" {...at("filter", "RIN1")}
        connections={{ pin1: N.bpfIn, pin2: ".U_BPF > .INV_B" }} />
      <resistor name="RQ1" resistance="47.9k" footprint="0603" {...at("filter", "RQ1")}
        connections={{ pin1: ".U_BPF > .INV_B", pin2: ".U_BPF > .V1_B" }} />
      <resistor name="R21" resistance="12.8k" footprint="0603" {...at("filter", "R21")}
        connections={{ pin1: ".U_BPF > .INV_B", pin2: ".U_BPF > .V2_B" }} />
      <resistor name="RIN2" resistance="47.9k" footprint="0603" {...at("filter", "RIN2")}
        connections={{ pin1: ".U_BPF > .V1_B", pin2: ".U_BPF > .INV_A" }} />
      <resistor name="RQ2" resistance="47.9k" footprint="0603" {...at("filter", "RQ2")}
        connections={{ pin1: ".U_BPF > .INV_A", pin2: ".U_BPF > .V1_A" }} />
      <resistor name="R22" resistance="12.8k" footprint="0603" {...at("filter", "R22")}
        connections={{ pin1: ".U_BPF > .INV_A", pin2: ".U_BPF > .V2_A" }} />
      <resistor name="RIN3" resistance="47.9k" footprint="0603" {...at("filter", "RIN3")}
        connections={{ pin1: ".U_BPF > .V1_A", pin2: ".U_BPF > .INV_C" }} />
      <resistor name="RQ3" resistance="47.9k" footprint="0603" {...at("filter", "RQ3")}
        connections={{ pin1: ".U_BPF > .INV_C", pin2: ".U_BPF > .V1_C" }} />
      <resistor name="R23" resistance="12.8k" footprint="0603" {...at("filter", "R23")}
        connections={{ pin1: ".U_BPF > .INV_C", pin2: ".U_BPF > .V2_C" }} />
      <resistor name="RIN4" resistance="47.9k" footprint="0603" {...at("filter", "RIN4")}
        connections={{ pin1: ".U_BPF > .V1_C", pin2: ".U_BPF > .INV_D" }} />
      <resistor name="RQ4" resistance="47.9k" footprint="0603" {...at("filter", "RQ4")}
        connections={{ pin1: ".U_BPF > .INV_D", pin2: ".U_BPF > .V1_D" }} />
      <resistor name="R24" resistance="12.8k" footprint="0603" {...at("filter", "R24")}
        connections={{ pin1: ".U_BPF > .INV_D", pin2: ".U_BPF > .V2_D" }} />
      {/* AGND is bypassed locally with a short return; it is not a general-purpose source. */}
      <capacitor name="CBPF1" capacitance="1uF" footprint="0603" {...at("filter", "CBPF1")}
        connections={{ pin1: ".U_BPF > .AGND", pin2: GND }} />
      <capacitor name="CBPF2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("filter", "CBPF2")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      {/* filter output node: the last section's band-pass output V1_D */}
      <trace from=".U_BPF > .V1_D" to={N.bpfOut} />
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
        pinLabels={pinLabelsOf("U_PGA")}
        pinAttributes={{ V_PLUS: { requiresPower: true }, V_MINUS: { requiresGround: true } }}
        connections={{
          INA: N.pgaIn,
          OUTA: N.pgaOut,
          V_PLUS: N.v5afe,
          V_MINUS: GND,
          DGND: GND,
          // INB/OUTB/DOUT and the three no-connect pads stay open: Rev.0 only
          // uses channel A, and DOUT is a 5 V logic output we do not read back.
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
      <capacitor name="CPGA2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("pga", "CPGA2")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      {/* PGA powers up enabled whenever 5V_AFE is present */}
      <resistor name="RPGA_SHDN" resistance="100k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25741"] }} {...at("pga", "RPGA_SHDN")}
        connections={{ pin1: ".U_PGA > .SHDN", pin2: GND }} />
      {/* ~100 ohm source-series resistors near the ECP5 on the low-rate SPI bus */}
      <resistor name="RS_PGA_SCK" resistance="100" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25076"] }} {...at("pga", "RS_PGA_SCK")}
        connections={{ pin1: N.pgaSck, pin2: N.pgaSckF }} />
      <resistor name="RS_PGA_MOSI" resistance="100" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25076"] }} {...at("pga", "RS_PGA_MOSI")}
        connections={{ pin1: N.pgaMosi, pin2: N.pgaMosiF }} />
      <resistor name="RS_PGA_CS" resistance="100" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25076"] }} {...at("pga", "RS_PGA_CS")}
        connections={{ pin1: N.pgaCsN, pin2: N.pgaCsF }} />
      <trace from=".RS_PGA_SCK > .pin2" to=".U_PGA > .CLK" />
      <trace from=".RS_PGA_MOSI > .pin2" to=".U_PGA > .DIN" />
      <trace from=".RS_PGA_CS > .pin2" to=".U_PGA > .CS_LD" />
    </>
  );
}
