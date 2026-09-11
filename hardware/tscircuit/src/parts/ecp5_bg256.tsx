/**
 * Lattice ECP5 LFE5U-45F-7BG256I — BG256 ball-accurate wrapper.
 *
 * SAFETY CRITICAL. Ball identity comes from ../../pin-plan.json, never from the
 * generic footprinter BGA generator: footprinter names the 16 rows A..P, while a
 * real BG256 uses A..T with I/O/Q/S omitted. Using the generic names here would
 * silently renumber the FPGA and is exactly the failure mode
 * docs/14-hardware-cad-tscircuit.md forbids.
 *
 * The chip therefore keeps footprinter's `bga256` *geometry* (16x16, 0.8 mm,
 * row-major from the top-left corner) and overrides every pad label with the
 * audited Lattice ball name. scripts/verify-bga-identity.ts proves the geometry
 * still matches pin-plan.json, and fails the build gate if it ever drifts.
 */
import pinPlan from "../../pin-plan.json";
import { N } from "./nets";

export type Ball = {
  ball: string;
  pad: number;
  row: string;
  col: number;
  signal: string | null;
  kind: string;
  bank: number | null;
  audit: string;
};

export const BALLS: Ball[] = (pinPlan as { balls: Ball[] }).balls;
export const DEVICE = pinPlan.device;
export const IDENTITY_SHA256 = (pinPlan as any).ball_audit?.identity_sha256;

export const UNASSIGNED_BALLS = BALLS.filter((b) => b.audit !== "documented").map((b) => b.ball);

// ---------------------------------------------------------------------------
// build-time guard: the wrapper refuses to build on a tampered pin plan
// ---------------------------------------------------------------------------
const ROW_LETTERS = [..."ABCDEFGHJKLMNPRT"];
function assertBallPlanIntegrity() {
  if (BALLS.length !== 256) {
    throw new Error(`pin-plan.json must describe 256 BG256 balls, found ${BALLS.length}`);
  }
  const ordered = [...BALLS].sort((a, b) => a.pad - b.pad);
  ordered.forEach((b, i) => {
    const expRow = ROW_LETTERS[Math.floor(i / 16)];
    const expCol = (i % 16) + 1;
    if (b.pad !== i + 1 || b.ball !== `${expRow}${expCol}` || b.row !== expRow || b.col !== expCol) {
      throw new Error(
        `BG256 ball identity drift at pad ${i + 1}: expected ${expRow}${expCol}, ` +
        `pin-plan.json has ${b.ball} (row ${b.row}, col ${b.col}). ` +
        `Run scripts/verify-bga-identity.ts before building.`,
      );
    }
  });
  if (!IDENTITY_SHA256) {
    throw new Error("pin-plan.json has no ball_audit.identity_sha256 — ball identity is not frozen");
  }
}
assertBallPlanIntegrity();

/** pinN -> audited Lattice ball name. */
export const ECP5_PIN_LABELS: Record<string, string> = Object.fromEntries(
  BALLS.map((b) => [`pin${b.pad}`, b.ball]),
);

/** Lattice ball name -> pad number, for constraint/LPF generation. */
export const ECP5_BALL_TO_PAD: Record<string, number> = Object.fromEntries(
  BALLS.map((b) => [b.ball, b.pad]),
);

// ---------------------------------------------------------------------------
// connectivity
// ---------------------------------------------------------------------------
const SIGNAL_NETS: Record<string, string> = {
  CLK_25M: N.clk25m,
  ADC_SCK: N.adcSck,
  ADC_SDO: N.adcSdo,
  ADC_CONV: N.adcConv,
  PGA_SCK: N.pgaSck,
  PGA_MOSI: N.pgaMosi,
  PGA_CS_N: N.pgaCsN,
  PPS_REF: N.ppsRef,
  LCD_SCL: N.lcdScl,
  LCD_SDA: N.lcdSda,
  LCD_RST_N: N.lcdRstN,
  LCD_BL_EN: N.lcdBlEn,
  HAT_SPI_MOSI: N.spiMosi,
  HAT_SPI_MISO: N.spiMiso,
  HAT_SPI_SCLK: N.spiSclk,
  HAT_SPI_CS_N: N.spiCsN,
  HAT_IRQ: N.irq,
  HAT_RESET_N: N.resetN,
  HAT_PPS: N.hatPps,
  HAT_UART_TX: N.uartTx,
  HAT_UART_RX: N.uartRx,
};

const FLASH_NETS: Record<string, string> = {
  CSSPIN: N.flashCsN,
  MCLK: N.flashClk,
  D0_MOSI: N.flashMosi,
  D1_MISO: N.flashMiso,
  CSN: N.flashCsN,
};

const JTAG_NETS: Record<string, string> = {
  TCK: N.jtagTck,
  TMS: N.jtagTms,
  TDI: N.jtagTdi,
  TDO: N.jtagTdo,
};

export const ECP5_CONNECTIONS: Record<string, string> = (() => {
  const conns: Record<string, string> = {};
  for (const b of BALLS) {
    const sig = b.signal;
    if (!sig) continue;
    if (sig.startsWith("VCCIO")) {
      conns[b.ball] = N.v3v3d;
    } else if (sig === "VCC") {
      conns[b.ball] = N.v1v1core;
    } else if (sig === "VCCAUX") {
      conns[b.ball] = N.v2v5aux;
    } else if (SIGNAL_NETS[sig]) {
      conns[b.ball] = SIGNAL_NETS[sig];
    } else if (FLASH_NETS[sig]) {
      conns[b.ball] = FLASH_NETS[sig];
    } else if (JTAG_NETS[sig]) {
      conns[b.ball] = JTAG_NETS[sig];
    }
    // CFG0/CFG1/CFG2, PROGRAMN, INITN, DONE, WRITEN, CS1N, DOUT_CSON, R7/P7/N7/M7
    // and every `unverified` ball stay intentionally unconnected: their identity
    // is not yet cross-checked against FPGA-SC-02034 and an invented net here
    // could silently miswire the FPGA. See pin-plan.json -> ball_audit.
  }
  return conns;
})();

/** Ball names that carry a net in the generated netlist. */
export const ECP5_CONNECTED_BALLS = Object.keys(ECP5_CONNECTIONS);

/** Ball names reserved for configuration straps / status, wired through pulls. */
export const ECP5_CONFIG_BALLS = {
  cfg0: "N10",
  cfg1: "P10",
  cfg2: "R10",
  programn: "R9",
  initn: "T9",
  done: "P9",
} as const;
