/**
 * Local receiver power tree (HAT+ only, Rev.0).
 *
 * docs/19-power-tree.md, docs/26-hat-power.md, docs/28-power-passives-sequencing.md:
 *
 *   PI_5V  -> TPS22975NDSGR -> 5V_SYS           (power/hat_5v_input.tsx)
 *                               +--> 0.10 ohm -> 5V_AFE -> OPA810/LTC1562/LTC6912
 *                               +--> LT3042    -> 3V3_ADC_A -> ADC/driver
 *                               +--> TPS7A2033 -> 3V3_CLK   -> SiT5356
 *                               +--> TPS628502 -> 1V1_CORE  -> ECP5 VCC
 *   PI_3V3 -> 0R/current-measure link -> 3V3_D -> VCCIO* / flash / LCD / I-O
 *                                             -> TPS7A2025 -> 2V5_AUX -> ECP5 VCCAUX
 *
 * The only local switcher is the 1.1 V core buck and it lives in the digital
 * region: 29 x 77.5 kHz = 2.2475 MHz, so the 2.25 MHz default is deliberately
 * avoided and forced PWM is used with spread spectrum disabled.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";

const GND = N.gnd;

/** 5V_AFE fixed filter branch (no LC tuning, no selectable resistor). */
export function AnalogRailBranch() {
  return (
    <>
      <resistor name="CAFE_R" resistance="0.10" footprint="0805" {...at("power_1v1", "CAFE_R")}
        connections={{ pin1: N.v5sys, pin2: N.v5afe }} />
      <capacitor name="CAFE1" capacitance="100uF" footprint="1210" {...at("power_1v1", "CAFE1")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      <capacitor name="CAFE2" capacitance="1uF" footprint="0603" {...at("power_1v1", "CAFE2")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
      <capacitor name="CAFE3" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("power_1v1", "CAFE3")}
        connections={{ pin1: N.v5afe, pin2: GND }} />
    </>
  );
}

/** Sole local switching regulator: 5V_SYS -> 1V1_CORE (ECP5 core). */
export function CoreBuck() {
  return (
    <>
      <chip
        name="U_CORE"
        footprint="sot563"
        {...at("power_1v1", "U_CORE")}
        pinLabels={{
          pin1: "VIN", pin2: "GND", pin3: "SW", pin4: "FB",
          pin5: "COMP_FSET", pin6: "MODE_SYNC", pin7: "EN", pin8: "VOS",
        }}
        pinAttributes={{ VIN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          VIN: N.v5sys,
          EN: N.v5sys,
          COMP_FSET: ".RFSET > .pin1",
          MODE_SYNC: ".RMODE > .pin2",
          GND: GND,
        }}
      />
      {/* L = DFE252012PD-R47M=P2, 0.47 uH shielded, immediately at the switch node */}
      <inductor name="L_CORE" inductance="470nH" footprint="0402" {...at("power_1v1", "L_CORE")}
        connections={{ pin1: ".U_CORE > .SW", pin2: N.v1v1core }} />
      <capacitor name="CIN_CORE1" capacitance="10uF" footprint="0805" {...at("power_1v1", "CIN_CORE1")}
        connections={{ pin1: N.v5sys, pin2: GND }} />
      <capacitor name="CIN_CORE2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("power_1v1", "CIN_CORE2")}
        connections={{ pin1: N.v5sys, pin2: GND }} />
      <capacitor name="COUT_CORE1" capacitance="10uF" footprint="0805" {...at("power_1v1", "COUT_CORE1")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="COUT_CORE2" capacitance="10uF" footprint="0805" {...at("power_1v1", "COUT_CORE2")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      {/* FSET 5.76 kOhm -> ~3.125 MHz nominal, SSC off, forced PWM */}
      <resistor name="RFSET" resistance="5.76k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C5153969"] }} {...at("power_1v1", "RFSET")}
        connections={{ pin1: ".U_CORE > .COMP_FSET", pin2: GND }} />
      {/* MODE/SYNC high through 10 kOhm */}
      <resistor name="RMODE" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("power_1v1", "RMODE")}
        connections={{ pin1: N.v5sys, pin2: ".U_CORE > .MODE_SYNC" }} />
      {/* feedback 39.2 k / 47.0 k / 10 pF C0G -> 1.100 V */}
      <resistor name="RFB_TOP" resistance="39.2k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C137996"] }} {...at("power_1v1", "RFB_TOP")}
        connections={{ pin1: N.v1v1core, pin2: ".U_CORE > .FB" }} />
      <resistor name="RFB_BOT" resistance="47.0k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25792"] }} {...at("power_1v1", "RFB_BOT")}
        connections={{ pin1: ".U_CORE > .FB", pin2: GND }} />
      <capacitor name="CFF_CORE" capacitance="10pF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C32949"] }} {...at("power_1v1", "CFF_CORE")}
        connections={{ pin1: N.v1v1core, pin2: ".U_CORE > .FB" }} />
      <trace from={N.v1v1core} to=".U_CORE > .VOS" />
    </>
  );
}

/** PI_3V3 -> 3V3_D entry link and 2V5_AUX for the ECP5 auxiliary supply. */
export function DigitalRails() {
  return (
    <>
      {/* 0R / current-measure link; the measurement point is not taken from any
          other rail and no alternate supply may drive 3V3_D while PI_3V3 is absent. */}
      <resistor name="R3V3D_LINK" resistance="0" footprint="0805" {...at("ecp5_flash", "R3V3D_LINK")}
        connections={{ pin1: N.pi3v3, pin2: N.v3v3d }} />
      <capacitor name="C3V3D1" capacitance="10uF" footprint="0805" {...at("ecp5_flash", "C3V3D1")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="C3V3D2" capacitance="1uF" footprint="0603" {...at("ecp5_flash", "C3V3D2")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="C3V3D3" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "C3V3D3")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />

      <chip
        name="U_AUXLDO"
        footprint="sot23-5"
        {...at("power_1v1", "U_AUXLDO")}
        pinLabels={{ pin1: "IN", pin2: "GND", pin3: "EN", pin4: "NC", pin5: "OUT" }}
        pinAttributes={{ IN: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ IN: N.v3v3d, EN: N.v3v3d, OUT: N.v2v5aux, GND: GND }}
      />
      <capacitor name="CAUXLDO_IN" capacitance="2.2uF" footprint="0603" {...at("power_1v1", "CAUXLDO_IN")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="CAUXLDO_OUT" capacitance="2.2uF" footprint="0603" {...at("power_1v1", "CAUXLDO_OUT")}
        connections={{ pin1: N.v2v5aux, pin2: GND }} />
    </>
  );
}
