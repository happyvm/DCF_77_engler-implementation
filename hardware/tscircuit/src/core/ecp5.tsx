/**
 * ECP5 LFE5U-45F-7BG256I, configuration flash, sysCONFIG straps, JTAG recovery
 * and the ECP5 decoupling baseline.
 *
 * docs/23-ecp5-boot-config.md: Master SPI single-bit boot (CFGMDN[2:0] = 010),
 * W25Q64JVSSIQ flash, exact Bank-8 ball map, pull-up/pull-down policy, JTAG pull
 * policy, and "no decorative routing on unused Bank-8 configuration pins".
 * docs/19 §"ECP5 decoupling baseline".
 *
 * The ball labels come from src/parts/ecp5_bg256.tsx, which is generated from the
 * audited pin-plan.json. Never renumber or reorder them by hand: the KiCad export
 * is gated by scripts/verify-bga-identity.ts.
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";
import { BALLS, ECP5_CONNECTIONS, ECP5_PIN_LABELS } from "../parts/ecp5_bg256";
import { pinLabelsOf } from "../parts/pinouts";

const GND = N.gnd;

/** Power-ball attributes derived from pin-plan.json (never hand-typed). */
const ECP5_PIN_ATTRIBUTES = Object.fromEntries(
  BALLS.filter((b) => b.kind === "power").map((b) => [
    b.ball,
    { requiresPower: true, providesPower: true },
  ]),
);

export function Ecp5AndConfiguration() {
  return (
    <>
      <chip
        name="U1"
        footprint="bga256"
        {...at("ecp5_core", "U1")}
        pinLabels={ECP5_PIN_LABELS}
        pinAttributes={ECP5_PIN_ATTRIBUTES}
        connections={ECP5_CONNECTIONS}
      />

      {/* ---------------------------------------------------------------- */}
      {/* configuration flash: W25Q64JVSSIQ, SOIC-8 208 mil                */}
      {/* ---------------------------------------------------------------- */}
      <chip
        name="U_FLASH"
        footprint="soic8"
        {...at("ecp5_flash", "U_FLASH")}
        pinLabels={pinLabelsOf("U_FLASH")}
        pinAttributes={{ VCC: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{
          CS_N: N.flashCsN,
          CLK: N.flashClk,
          DI_IO0: N.flashMosi,
          DO_IO1: N.flashMiso,
          VCC: N.v3v3d,
          GND: GND,
        }}
      />
      {/* ECP5 Master-SPI pulls: MOSI/MISO 10k, CSSPIN 4.7k, MCLK 1k */}
      <resistor name="RFLASH1" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("ecp5_flash", "RFLASH1")}
        connections={{ pin1: N.v3v3d, pin2: N.flashMosi }} />
      <resistor name="RFLASH2" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("ecp5_flash", "RFLASH2")}
        connections={{ pin1: N.v3v3d, pin2: N.flashMiso }} />
      <resistor name="RFLASH3" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RFLASH3")}
        connections={{ pin1: N.v3v3d, pin2: N.flashCsN }} />
      <resistor name="RFLASH4" resistance="1k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C11702"] }} {...at("ecp5_flash", "RFLASH4")}
        connections={{ pin1: N.v3v3d, pin2: N.flashClk }} />
      {/* flash-side unused serial pins tied off */}
      <resistor name="RFLASH5" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("ecp5_flash", "RFLASH5")}
        connections={{ pin1: N.v3v3d, pin2: ".U_FLASH > .WP_IO2" }} />
      <resistor name="RFLASH6" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("ecp5_flash", "RFLASH6")}
        connections={{ pin1: N.v3v3d, pin2: ".U_FLASH > .HOLD_IO3" }} />

      {/* ---------------------------------------------------------------- */}
      {/* sysCONFIG straps: CFG1 = 4.7k -> VCCIO8, CFG0 = 0R -> GND,      */}
      {/* CFG2 = 0R -> GND  (Master SPI, single-bit)                       */}
      {/* ---------------------------------------------------------------- */}
      <resistor name="RCFG0" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RCFG0")}
        connections={{ pin1: N.v3v3d, pin2: ".U1 > .P10" }} />
      <resistor name="RCFG1" resistance="0" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C17168"] }} {...at("ecp5_flash", "RCFG1")}
        connections={{ pin1: ".U1 > .R10", pin2: GND }} />
      <trace from=".U1 > .N10" to={GND} />

      {/* configuration status/control pulls */}
      <resistor name="RPROG" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RPROG")}
        connections={{ pin1: N.v3v3d, pin2: ".U1 > .R9" }} />
      <resistor name="RINIT" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RINIT")}
        connections={{ pin1: N.v3v3d, pin2: ".U1 > .T9" }} />
      <resistor name="RDONE" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RDONE")}
        connections={{ pin1: N.v3v3d, pin2: ".U1 > .P9" }} />

      {/* ---------------------------------------------------------------- */}
      {/* JTAG recovery: mandatory even though normal boot is from flash    */}
      {/* ---------------------------------------------------------------- */}
      <resistor name="RTDI" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RTDI")}
        connections={{ pin1: N.v3v3d, pin2: N.jtagTdi }} />
      <resistor name="RTMS" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RTMS")}
        connections={{ pin1: N.v3v3d, pin2: N.jtagTms }} />
      <resistor name="RTDO" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RTDO")}
        connections={{ pin1: N.v3v3d, pin2: N.jtagTdo }} />
      <resistor name="RTCK" resistance="4.7k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25900"] }} {...at("ecp5_flash", "RTCK")}
        connections={{ pin1: N.jtagTck, pin2: GND }} />
      <chip
        name="J2"
        footprint="pinheader6"
        {...at("ecp5_flash", "J2")}
        pinLabels={{ pin1: "TCK", pin2: "TMS", pin3: "TDI", pin4: "TDO", pin5: "3V3_D_REF", pin6: "GND" }}
        pinAttributes={{ "3V3_D_REF": { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ TCK: N.jtagTck, TMS: N.jtagTms, TDI: N.jtagTdi, TDO: N.jtagTdo, "3V3_D_REF": N.v3v3d, GND: GND }}
      />

      {/* ---------------------------------------------------------------- */}
      {/* decoupling baseline                                               */}
      {/* ---------------------------------------------------------------- */}
      {/* 1V1_CORE: 6 x 100 nF (one per VCC ball) + 2 x 10 uF bulk */}
      <capacitor name="CORE1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE1")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE2")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE3" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE3")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE4" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE4")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE5" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE5")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE6" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CORE6")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE7" capacitance="10uF" footprint="0805" {...at("ecp5_flash", "CORE7")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />
      <capacitor name="CORE8" capacitance="10uF" footprint="0805" {...at("ecp5_flash", "CORE8")}
        connections={{ pin1: N.v1v1core, pin2: GND }} />

      {/* 2V5_AUX: 2 x 100 nF (one per VCCAUX ball) + 4.7 uF bulk */}
      <capacitor name="CAUX1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CAUX1")}
        connections={{ pin1: N.v2v5aux, pin2: GND }} />
      <capacitor name="CAUX2" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CAUX2")}
        connections={{ pin1: N.v2v5aux, pin2: GND }} />
      <capacitor name="CAUX3" capacitance="4.7uF" footprint="0603" {...at("ecp5_flash", "CAUX3")}
        connections={{ pin1: N.v2v5aux, pin2: GND }} />

      {/* 3V3_D: 100 nF per VCCIO supply ball, 1 uF per populated bank, 10 uF at
          Bank 8 / W25Q64 and at the main ECP5 entry */}
      <capacitor name="CVIO8" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("ecp5_flash", "CVIO8")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="CVIOBANK" capacitance="1uF" footprint="0603" {...at("ecp5_flash", "CVIOBANK")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
    </>
  );
}
