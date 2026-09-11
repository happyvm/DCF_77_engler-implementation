/**
 * Raspberry Pi Standard HAT+ mechanics, locked placements and constrained regions.
 *
 * Source of intent: docs/14-hardware-cad-tscircuit.md
 *   - "Locked before Quilter": the header, holes/outline, ferrite, antenna tuning,
 *     OPA810 input cluster, LCD mechanics and the external PPS/test interface.
 *   - "Constrained regions": Quilter may optimise *inside* the listed regions only.
 *   - "Hard layout constraints": the analog/digital separation rules.
 *
 * Everything in this file is enforced twice:
 *   1. at build time — component coordinates come from these tables and the
 *      mandatory relations are emitted as real <constraint> elements;
 *   2. at check time — scripts/validate-design-plans.ts asserts region membership,
 *      region containment, locked coordinates and that no two parts overlap.
 *
 * Floorplan (left = quiet analog, right = digital, header along the top edge):
 *
 *   x   -32.5 ....... -17 | -16.5 .. -3.5 | -3 ........ 12 | 13 ......... 32.5
 *   y   quiet ferrite/AFE | filter        | ADC           | LCD
 *       (locked cluster)  | PGA           | 1V1 power     | ECP5 flash
 *                         |               | Pi host I-O   | ECP5 / TCXO
 *
 * The analog/digital boundary sits at x = -3: the digital column (ADC + 1.1 V power
 * + Pi host) needs 15 mm of usable width for 59 parts, so the LTC1562/LTC6912 column
 * was narrowed to 13 mm, which still packs with margin.
 */
export type RegionId =
  | "ferrite_afe"
  | "filter"
  | "pga"
  | "adc"
  | "power_1v1"
  | "tcxo"
  | "ecp5_core"
  | "ecp5_flash"
  | "host_debug"
  | "lcd";

export type LockedPlacement = {
  x: number;
  y: number;
  rotation?: number;
  region: RegionId;
  reason: string;
};

export const BOARD_MM = {
  width: 65.0,
  height: 56.5,
  thickness: 1.6,
  layers: 4 as const,
  origin: "board centre; x grows to the right, y grows toward the Raspberry Pi header edge",
  note: "Raspberry Pi Standard HAT+ outline. Confirm against the current HAT+ mechanical drawing before fabrication.",
} as const;

export const HAT_HEADER = {
  ref: "J1",
  x: 0,
  y: 24.0,
  rotation: 0,
  rows: 2,
  cols: 20,
  pitch: 2.54,
  reason: "HAT+ mating position is fixed by the Raspberry Pi 40-pin layout.",
} as const;

export const MOUNTING_HOLES = [
  { ref: "H1", x: -29.0, y: 24.75 },
  { ref: "H2", x: 29.0, y: 24.75 },
  { ref: "H3", x: -29.0, y: -24.75 },
  { ref: "H4", x: 29.0, y: -24.75 },
] as const;

/** Quilter must not move these. x/y are the locked board coordinates in mm. */
export const LOCKED_PLACEMENTS: Record<string, LockedPlacement> = {
  ANT1: {
    x: -24.7, y: -17.2, rotation: 0, region: "ferrite_afe",
    reason: "integrated ferrite at the board edge farthest from the Pi header, ECP5 and the switching regulator; X magnetic axis along the board Y axis; pulled clear of mounting hole H3 by 0.7 mm so the ferrite pads cannot land on the hole",
  },
  CANT1: { x: -30.9, y: -10.5, region: "ferrite_afe", reason: "560 pF tuning network immediately beside the antenna pads, on the quiet row above the ferrite" },
  CANT2: { x: -27.35, y: -10.5, region: "ferrite_afe", reason: "22 pF tuning network immediately beside the antenna pads, on the quiet row above the ferrite" },
  RANT: { x: -23.8, y: -10.5, region: "ferrite_afe", reason: "330 kOhm damping resistor immediately beside the antenna pads, on the quiet row above the ferrite" },
  U_BUF: { x: -27.0, y: -5.4, region: "ferrite_afe", reason: "OPA810 high-impedance input cluster directly above the tuned network; no long stub at the high-impedance node (y nudged 0.1 mm up so the rendered courtyards keep the >= 2.5 mm edge-to-edge gap to the CANT row)" },
  C_BUF: { x: -22.8, y: -5.5, region: "ferrite_afe", reason: "AC-coupling / bias interface capacitor kept at the OPA810 output" },
  U_PPS: { x: 9.5, y: 9.0, region: "host_debug", reason: "external PPS output buffer in the digital region, away from the ferrite; PPS_REF routes directly to it" },
};

/** Quilter may optimise placement inside these regions, but not outside them. */
export type Region = {
  id: RegionId;
  name: string;
  /** centre */
  x: number;
  y: number;
  width: number;
  height: number;
  quilter: "optimise";
  rules: string[];
  /** reference designators that must be placed inside this region */
  members: string[];
};

export const REGIONS: Region[] = [
  {
    id: "ferrite_afe",
    name: "quiet ferrite / AFE zone",
    x: -24.75, y: -12.125, width: 15.5, height: 32.25,
    quilter: "optimise",
    rules: [
      "no fast Pi/FPGA trace under the ferrite/input region",
      "no switching-regulator node or inductor nearby",
      "no ECP5 clock trace nearby",
      "minimise ANT_IN copper length",
      "no unused test stub on the high-impedance node",
    ],
    members: ["ANT1", "CANT1", "CANT2", "RANT", "U_BUF", "C_BUF", "R1", "R2", "CVCM1", "CVCM2", "CVCM3"],
  },
  {
    id: "filter",
    name: "LTC1562 band-pass region",
    x: -10.0, y: -17.125, width: 13.0, height: 22.25,
    quilter: "optimise",
    rules: [
      "place the eleven programming resistors immediately around the LTC1562 pins",
      "keep section-to-section nodes short",
      "no buck switch node, ECP5 clock, ADC SCK or Pi fast trace through the filter area",
      "bypass AGND locally with a short return",
    ],
    members: ["U_BPF", "RIN1", "RQ1", "R21", "RIN2", "RQ2", "R22", "RIN3", "RQ3", "R23", "RIN4", "RQ4", "R24", "CBPF1", "CBPF2"],
  },
  {
    id: "pga",
    name: "LTC6912 PGA region",
    x: -10.0, y: 0.5, width: 13.0, height: 11.5,
    quilter: "optimise",
    rules: [
      "1 uF coupling capacitor and 1 MOhm bias resistor immediately at the PGA input",
      "AGND bypass parts directly beside the IC",
      "no PGA SPI routing underneath the ferrite or filter sections",
      "keep the PGA output route short to the ADC / OPA2835 island",
    ],
    members: ["U_PGA", "C_PGAIN", "R_PGABIAS", "CPGA1", "CPGA2", "RPGA_SHDN", "RS_PGA_SCK", "RS_PGA_MOSI", "RS_PGA_CS"],
  },
  {
    id: "adc",
    name: "ADC / driver / LT3042 region",
    // Grows upward from the board edge: the LTC1407A + OPA2835 + LT3042 cluster plus
    // its decoupling/reference/VCM network need 17.0 mm, and the bottom edge is the
    // board outline (-28.25 mm), so the extra height is taken from the digital side.
    x: 4.5, y: -19.75, width: 15.0, height: 17.0,
    quilter: "optimise",
    rules: [
      "ADC sits on the analog/digital boundary",
      "LT3042, OPA2835 and ADC decoupling stay compact",
      "ADC digital signals leave toward the ECP5",
      "reference/common-mode network protected from digital return currents",
    ],
    members: [
      "U_ADC", "U_DRV", "U_ADCLDO", "RSET_ADC", "CSET_ADC",
      "CADC1", "CADC2", "CADC3", "CADC4", "CREF1",
      "R_ADCIN_P", "R_ADCIN_N", "C_ADCIN", "R_VCMADC1", "R_VCMADC2",
    ],
  },
  {
    id: "power_1v1",
    name: "1.1 V core power region",
    x: 4.5, y: -4.5, width: 15.0, height: 15.0,
    quilter: "optimise",
    rules: [
      "the sole local switching buck lives in the digital region only",
      "minimum practical SW copper area",
      "inductor immediately adjacent to the switch node / output capacitors",
      "VIN capacitor immediately adjacent to VIN/GND",
    ],
    members: [
      "U_CORE", "L_CORE", "CIN_CORE1", "CIN_CORE2", "COUT_CORE1", "COUT_CORE2",
      "RFSET", "RMODE", "RFB_TOP", "RFB_BOT", "CFF_CORE",
      "U_SW", "RON_PD", "CT_SW", "CAFE_R", "CAFE1", "CAFE2", "CAFE3",
      "U_AUXLDO", "CAUXLDO_IN", "CAUXLDO_OUT",
    ],
  },
  {
    id: "host_debug",
    name: "Raspberry Pi host / PPS / ID-EEPROM region",
    // Height extended from 17.0 to 18.0 mm (top edge unchanged at y = 21.0, bounded by
    // the HAT header courtyard) to seat D_ESD_PPS, the ESD clamp at the external
    // PPS/test header J3. The bottom edge moves onto the power_1v1 boundary at
    // y = 3.0, reclaiming the 1 mm strip that was previously unused.
    x: 4.5, y: 12.0, width: 15.0, height: 18.0,
    quilter: "optimise",
    rules: [
      "HAT SPI/UART stays in the digital/top region",
      "UART activity normally confined to the end-of-second tail",
      "PPS_REF routes directly to the output buffer/connector",
      "no Bank 1/2/3 fast signal detours through the ferrite/OPA810 region",
    ],
    members: [
      "U_EE", "J3", "U_PPS", "RPS1",
      "RS_UART_TX", "RS_UART_RX", "RUART_TX", "RUART_RX",
      "RS_SPI_SCLK", "RS_SPI_MOSI", "RS_SPI_MISO", "RS_SPI_CS",
      "RRST", "RIRQ", "RTPS_UP", "RTPS_DN",
      "REESD", "REESC", "REEWP", "CEE1", "CVD1", "CVD2", "CVD3",
      // Clamps are listed last so the first-fit placer tucks them into residual
      // space instead of fragmenting the scan for the host interface parts.
      "D_ESD_PPS", "D_ESD_REF",
    ],
  },
  {
    id: "ecp5_core",
    name: "ECP5 BG256 region",
    // Height is set by the BG256 *rendered* courtyard (15.85 x 15.95 mm), not by its
    // pad spread (12.70 mm). The region spans y = -1.0 .. 15.0 so the FPGA courtyard,
    // centred at y = 7, stays inside it with margin; the flash region below starts at
    // y = -1.0 accordingly. Left edge is 12.0 to reclaim the 1 mm gap against the
    // analog/digital boundary column (the ADC region ends at x = 12).
    x: 22.25, y: 7.0, width: 20.5, height: 16.0,
    quilter: "optimise",
    rules: [
      "ECP5 BGA escape and plane continuity reviewed manually",
      "no Bank 1/2/3 fast signal detours through the ferrite/OPA810 region",
      "unused Bank 6/7 pins get no decorative test routing",
    ],
    members: ["U1"],
  },
  {
    id: "ecp5_flash",
    name: "ECP5 configuration flash / JTAG / decoupling region",
    // 34 members (flash, JTAG, decoupling) at their *rendered* courtyards need
    // ~215 mm^2; the region reaches down to the LCD zone edge (y = -20.45) and left
    // to x = 12.0 so the first-fit placer still has margin.
    x: 22.25, y: -10.725, width: 20.5, height: 19.45,
    quilter: "optimise",
    rules: [
      "flash adjacent to Bank 8",
      "MCLK/CSSPIN/MOSI/MISO short and local",
      "no configuration clock route toward ferrite/OPA810/LTC1562",
      "JTAG footprint reachable from the board edge",
      "no decorative routing on unused Bank-8 configuration pins",
    ],
    members: [
      "U_FLASH", "J2",
      "RFLASH1", "RFLASH2", "RFLASH3", "RFLASH4", "RFLASH5", "RFLASH6",
      "RCFG0", "RCFG1", "RPROG", "RINIT", "RDONE", "RTDI", "RTMS", "RTDO", "RTCK",
      "CORE1", "CORE2", "CORE3", "CORE4", "CORE5", "CORE6", "CORE7", "CORE8",
      "CAUX1", "CAUX2", "CAUX3", "CVIO8", "CVIOBANK",
      "C3V3D1", "C3V3D2", "C3V3D3", "R3V3D_LINK",
    ],
  },
  {
    id: "tcxo",
    name: "TCXO / TPS7A2033 region",
    x: 22.75, y: 18.0, width: 19.5, height: 6.0,
    quilter: "optimise",
    rules: [
      "SiT5356 physically separated from the ferrite and the first analog stage",
      "short direct route to ECP5 C9",
      "no long clock test stub",
      "clock return current stays in the digital region",
    ],
    members: ["U_CLK", "U_CLKLDO", "CCLK_LDO_IN", "CCLK_LDO_OUT", "CCLK1"],
  },
  {
    id: "lcd",
    name: "LCD mechanical zone (locked)",
    x: 22.75, y: -24.125, width: 19.5, height: 8.25,
    quilter: "optimise",
    rules: [
      "LCD mechanical position/orientation locked before automated placement",
      "do not route I2C beneath the integrated ferrite",
      "keep backlight return current out of the analog input region",
      "module is wider than the HAT+ outline; overhang is intentional",
    ],
    members: ["DS1", "LCD_BLQ", "RBL1", "RBL2", "RLCD_SCL", "RLCD_SDA", "CBL1", "CBL2", "RBL3"],
  },
];

/**
 * Courtyard size (mm) per reference designator, MEASURED from the footprints
 * tscircuit actually renders (pad bounding box + 0.7 mm allowance) rather than
 * estimated. The pre-Quilter placer uses these rectangles, so they must not be
 * smaller than the real courtyards — validate-design-plans.ts re-checks that no
 * two of them overlap.
 *
 * Calibration procedure (repeat whenever a footprint changes):
 *   npm run export:circuit
 *   tsx scripts/measure-courtyards.ts   > printed table
 * A missing entry is a hard error (sizeOf throws), so a new part cannot silently
 * inherit an optimistic default.
 */
const SIZE_MM: Record<string, [number, number]> = {
  ANT1: [15.20, 10.90], C3V3D1: [3.60, 2.10], C3V3D2: [3.15, 1.70], C3V3D3: [2.30, 1.35], CADC1: [3.55, 2.10],
  CADC2: [2.30, 1.35], CADC3: [3.55, 2.10], CADC4: [2.30, 1.35], CAFE1: [4.80, 3.35], CAFE2: [3.15, 1.65],
  CAFE3: [2.30, 1.35], CAFE_R: [3.60, 2.15], CANT1: [3.15, 1.65], CANT2: [3.15, 1.65], CAUX1: [2.30, 1.35],
  CAUX2: [2.30, 1.35], CAUX3: [3.15, 1.65], CAUXLDO_IN: [3.20, 1.65], CAUXLDO_OUT: [3.20, 1.65], CBL1: [2.30, 1.35],
  CBL2: [3.15, 1.70], CBPF1: [3.20, 1.70], CBPF2: [2.30, 1.35], CCLK1: [2.30, 1.35], CCLK_LDO_IN: [3.15, 1.70],
  CCLK_LDO_OUT: [3.15, 1.70], CEE1: [2.30, 1.35], CFF_CORE: [2.30, 1.35], CIN_CORE1: [3.55, 2.10],
  CIN_CORE2: [2.30, 1.35], CORE1: [2.30, 1.35], CORE2: [2.30, 1.35], CORE3: [2.30, 1.35], CORE4: [2.30, 1.35],
  CORE5: [2.30, 1.35], CORE6: [2.30, 1.35], CORE7: [3.60, 2.10], CORE8: [3.60, 2.10], COUT_CORE1: [3.55, 2.10],
  COUT_CORE2: [3.55, 2.10], CPGA1: [3.20, 1.65], CPGA2: [2.30, 1.35], CREF1: [3.20, 1.70], CSET_ADC: [3.20, 1.70],
  CT_SW: [3.20, 1.65], CVCM1: [3.60, 2.10], CVCM2: [3.15, 1.65], CVCM3: [2.30, 1.35], CVD1: [2.30, 1.35],
  CVD2: [3.15, 1.65], CVD3: [3.55, 2.15], CVIO8: [2.30, 1.35], CVIOBANK: [3.15, 1.65], C_ADCIN: [3.20, 1.70],
  D_ESD_PPS: [1.80, 1.40], D_ESD_REF: [1.80, 1.40],
  C_BUF: [3.15, 1.65], C_PGAIN: [3.20, 1.65], DS1: [14.10, 2.10], J1: [50.80, 5.05], J2: [16.25, 3.55], J3: [11.20, 3.55], LCD_BLQ: [4.30, 3.40], L_CORE: [2.30, 1.35], R1: [3.15, 1.65], R2: [3.15, 1.65],
  R21: [3.20, 1.65], R22: [3.20, 1.70], R23: [3.20, 1.70], R24: [3.20, 1.70], R3V3D_LINK: [3.60, 2.10],
  RANT: [3.15, 1.65], RBL1: [3.60, 2.10], RBL2: [2.30, 1.35], RBL3: [2.30, 1.35], RCFG0: [2.30, 1.35], RCFG1: [2.30, 1.35],
  RDONE: [2.30, 1.35], REESC: [2.30, 1.35], REESD: [2.30, 1.35], REEWP: [2.30, 1.35], RFB_BOT: [2.30, 1.35],
  RFB_TOP: [2.30, 1.35], RFLASH1: [2.30, 1.35], RFLASH2: [2.30, 1.35], RFLASH3: [2.30, 1.35], RFLASH4: [2.30, 1.35],
  RFLASH5: [2.30, 1.35], RFLASH6: [2.30, 1.35], RFSET: [2.30, 1.35], RIN1: [3.20, 1.65], RIN2: [3.20, 1.65],
  RIN3: [3.20, 1.70], RIN4: [3.20, 1.70], RINIT: [2.30, 1.35], RIRQ: [2.30, 1.35], RLCD_SCL: [2.30, 1.35],
  RLCD_SDA: [2.30, 1.35], RMODE: [2.30, 1.35], RON_PD: [2.30, 1.35], RPGA_SHDN: [2.30, 1.35], RPROG: [2.30, 1.35],
  RPS1: [2.30, 1.35], RQ1: [3.20, 1.65], RQ2: [3.20, 1.65], RQ3: [3.20, 1.70], RQ4: [3.20, 1.70], RRST: [2.30, 1.35],
  RSET_ADC: [3.20, 1.70], RS_PGA_CS: [2.30, 1.35], RS_PGA_MOSI: [2.30, 1.35], RS_PGA_SCK: [2.30, 1.35],
  RS_SPI_CS: [2.30, 1.35], RS_SPI_MISO: [2.30, 1.35], RS_SPI_MOSI: [2.30, 1.35], RS_SPI_SCLK: [2.30, 1.35],
  RS_UART_RX: [2.30, 1.35], RS_UART_TX: [2.30, 1.35], RTCK: [2.30, 1.35], RTDI: [2.30, 1.35], RTDO: [2.30, 1.35],
  RTMS: [2.30, 1.35], RTPS_DN: [2.30, 1.35], RTPS_UP: [2.30, 1.35], RUART_RX: [2.30, 1.35], RUART_TX: [2.30, 1.35],
  R_ADCIN_N: [2.30, 1.35], R_ADCIN_P: [2.30, 1.35], R_PGABIAS: [3.20, 1.65], R_VCMADC1: [2.30, 1.35],
  R_VCMADC2: [2.30, 1.35], U1: [15.85, 15.95], U_ADC: [6.70, 3.85], U_ADCLDO: [6.05, 6.65], U_AUXLDO: [4.30, 3.40],
  U_BPF: [5.90, 12.85], U_BUF: [4.35, 3.40], U_CLK: [6.05, 2.80], U_CLKLDO: [4.35, 3.40], U_CORE: [2.80, 2.05],
  U_DRV: [6.55, 3.65], U_EE: [6.00, 5.55], U_FLASH: [6.05, 5.55], U_PGA: [5.90, 10.30], U_PPS: [4.30, 3.40],
  U_SW: [4.35, 3.50],
};

/**
 * Coordinates the placer must not encroach on (large and/or mechanically fixed parts).
 * Mirrors LOCKED_PLACEMENTS and adds the two parts centred in a single-purpose region.
 */
export const FIXED_PLACEMENTS: Record<string, { pcbX: number; pcbY: number }> = {
  ...Object.fromEntries(
    Object.entries(LOCKED_PLACEMENTS).map(([ref, p]) => [ref, { pcbX: p.x, pcbY: p.y }]),
  ),
  // only the two parts that must be centred in their (single-purpose) region
  U1: { pcbX: 22.75, pcbY: 7.0 },
  // LCD module stays horizontally centred in its zone, but is lifted above mounting
  // hole H4 (29, -24.75): at its former y it spanned x 15.7..29.8 and would have sat
  // on the hole, which is a real mechanical defect.
  DS1: { pcbX: 22.75, pcbY: -21.5 },
};

export function sizeOf(ref: string): [number, number] {
  const s = SIZE_MM[ref];
  if (!s) {
    throw new Error(
      `no courtyard size declared for "${ref}" in SIZE_MM — measure it (scripts/measure-courtyards.ts) ` +
      `before adding the part, so the placer cannot under-declare it`,
    );
  }
  return s;
}

/**
 * Deterministic pre-Quilter placer parameters.
 *
 * step      — scan resolution of the free-slot search, in mm;
 * clearance — minimum edge-to-edge distance kept between any two courtyards, in mm;
 * margin    — inset from the region boundary.
 *
 * Note that the declared courtyards in SIZE_MM are deliberately generous
 * (a 0402 passive is declared as 2.6x1.6 mm), so the effective copper-to-copper
 * gap is much larger than `clearance` in practice.
 *
 * Parts are never rotated by the placer: `at()` returns only pcbX/pcbY, so a
 * silent 90 deg rotation would desynchronise the declared courtyard from the
 * emitted footprint. `validate-design-plans.ts` asserts exactly that.
 */
export const PLACER = {
  step: 0.25,
  clearance: 0.25,
  margin: 0.4,
} as const;

export type Rect = { left: number; right: number; bottom: number; top: number };

export function rectOf(pcbX: number, pcbY: number, w: number, h: number): Rect {
  return { left: pcbX - w / 2, right: pcbX + w / 2, bottom: pcbY - h / 2, top: pcbY + h / 2 };
}

function expand(r: Rect, d: number): Rect {
  return { left: r.left - d, right: r.right + d, bottom: r.bottom - d, top: r.top + d };
}

function overlaps(a: Rect, b: Rect) {
  return a.left < b.right && a.right > b.left && a.bottom < b.top && a.top > b.bottom;
}

/**
 * Board-level obstacles the placer must avoid: the 40-pin HAT header and the four
 * HAT+ mounting holes. They are mechanical objects, not region members, but a part
 * placed on top of a mounting hole (the integrated ferrite is the obvious risk)
 * would be a real mechanical defect, so they are fed into the placer and into
 * validate-design-plans.ts.
 */
export function boardObstacles(): Array<{ ref: string; rect: Rect }> {
  const [hw, hh] = sizeOf(HAT_HEADER.ref);
  return [
    { ref: HAT_HEADER.ref, rect: rectOf(HAT_HEADER.x, HAT_HEADER.y, hw, hh) },
    ...MOUNTING_HOLES.map((h) => ({ ref: h.ref, rect: rectOf(h.x, h.y, 2.75, 2.75) })),
  ];
}

/**
 * Mandatory relations, emitted as real tscircuit <constraint> elements.
 * Distance values are millimetres. Each relation is satisfied by the locked /
 * preferred coordinates in this file; scripts/validate-design-plans.ts re-checks
 * that before the design is exported.
 */
export type Relation =
  | { kind: "sameY"; for: string[]; why: string }
  | { kind: "sameX"; for: string[]; why: string }
  | { kind: "xDist"; left: string; right: string; xDist: number; edgeToEdge?: true; why: string }
  | { kind: "yDist"; top: string; bottom: string; yDist: number; edgeToEdge?: true; why: string };

export const MANDATORY_RELATIONS: Relation[] = [
  { kind: "sameY", for: [".CANT1", ".CANT2", ".RANT"], why: "antenna tuning parts sit on one compact line beside the ferrite pads" },
  { kind: "yDist", top: ".U_BUF", bottom: ".CANT1", yDist: 2.5, edgeToEdge: true, why: "OPA810 high-impedance cluster directly above the tuned antenna network; ANT_IN must stay short" },
  { kind: "yDist", top: ".U_CLK", bottom: ".ANT1", yDist: 20.0, edgeToEdge: true, why: "SiT5356 physically separated from the ferrite / first analog stage" },
  { kind: "xDist", left: ".U_BUF", right: ".U_CORE", xDist: 20.0, edgeToEdge: true, why: "no switching-regulator node or inductor near the AFE" },
  { kind: "yDist", top: ".J1", bottom: ".ANT1", yDist: 30.0, edgeToEdge: true, why: "Pi supply/host current returns stay in the digital/HAT-header region" },
];

export const HARD_RULES: string[] = [
  "no fast Pi/FPGA trace under the ferrite/input region",
  "no switching-regulator node near the AFE",
  "SiT5356 physically separated from the ferrite / first analog stage",
  "1V1_CORE buck in the digital region only",
  "PI_3V3 distribution stays in the HAT/digital region",
  "PI_5V reaches the power tree without crossing the AFE first",
  "analog rails filtered/post-regulated as defined in power-plan.json",
];

export const NET_PRIORITY: string[] = [
  "antenna/input analog path",
  "filter/PGA/ADC analog path",
  "ADC reference/common-mode/power",
  "TCXO -> ECP5 clock",
  "FPGA power/configuration/JTAG",
  "ADC digital interface",
  "PGA/LCD low-rate control",
  "Raspberry Pi host SPI/debug last",
];

// --------------------------------------------------------------------------
// deterministic placement
// --------------------------------------------------------------------------
export function regionById(id: RegionId): Region {
  const r = REGIONS.find((x) => x.id === id);
  if (!r) throw new Error(`unknown region "${id}"`);
  return r;
}

/** Region members that the placer has to position (no fixed coordinate). */
export function packedMembers(region: Region): string[] {
  return region.members.filter((m) => !FIXED_PLACEMENTS[m]);
}

/**
 * Deterministic, obstacle-aware first-fit placement inside a region.
 *
 * For every member (in the fixed `members` order) the placer scans the region on
 * a `PLACER.step` grid, from the top edge downwards and left to right, and takes
 * the first slot that clears the region boundary, every fixed (locked/preferred)
 * part and every already-placed member by `PLACER.clearance`. When a part does
 * not fit upright it is retried rotated by 90 degrees.
 *
 * The result is a pure function of (regionId, member order, SIZE_MM,
 * FIXED_PLACEMENTS), so scripts/validate-design-plans.ts re-derives the very same
 * placement and asserts region containment + "no two parts overlap". Placements
 * are memoised per region because every component module calls `at()` separately.
 */
export function placeInRegion(regionId: RegionId, ref: string): { pcbX: number; pcbY: number } {
  const table = placeRegion(regionId);
  const found = table[ref];
  if (!found) {
    throw new Error(`ref "${ref}" is not a placer-positioned member of region "${regionId}"`);
  }
  return found;
}

const placementCache = new Map<RegionId, Record<string, { pcbX: number; pcbY: number }>>();

function placeRegion(regionId: RegionId): Record<string, { pcbX: number; pcbY: number }> {
  const cached = placementCache.get(regionId);
  if (cached) return cached;

  const r = regionById(regionId);
  const list = packedMembers(r);

  const obstacles = [
    ...r.members
      .filter((m) => FIXED_PLACEMENTS[m])
      .map((m) => {
        const [w, h] = sizeOf(m);
        const p = FIXED_PLACEMENTS[m];
        return expand(rectOf(p.pcbX, p.pcbY, w, h), PLACER.clearance / 2);
      }),
    ...boardObstacles().map((o) => expand(o.rect, PLACER.clearance / 2)),
  ];

  const left = r.x - r.width / 2 + PLACER.margin;
  const right = r.x + r.width / 2 - PLACER.margin;
  const top = r.y + r.height / 2 - PLACER.margin;
  const bottom = r.y - r.height / 2 + PLACER.margin;

  const placed: Rect[] = [];
  const out: Record<string, { pcbX: number; pcbY: number }> = {};

  for (const member of list) {
    const [w0, h0] = sizeOf(member);
    const best = firstFreeSlot(w0, h0, left, right, top, bottom, [...obstacles, ...placed]);
    if (!best) {
      throw new Error(
        `region "${regionId}" has no free slot for "${member}" (${w0}x${h0} mm): ` +
        `the region is full. Enlarge the region or reduce a declared part size.`,
      );
    }

    placed.push(expand(best, PLACER.clearance / 2));
    out[member] = { pcbX: round2((best.left + best.right) / 2), pcbY: round2((best.bottom + best.top) / 2) };
  }

  placementCache.set(regionId, out);
  return out;
}

function firstFreeSlot(
  w: number,
  h: number,
  left: number,
  right: number,
  top: number,
  bottom: number,
  blockedRects: Rect[],
): Rect | null {
  if (w > right - left + 1e-9 || h > top - bottom + 1e-9) return null;
  const clear = PLACER.clearance / 2;
  const yFrom = top - h;
  const xMax = right - w;
  const ySteps = Math.floor((yFrom - bottom) / PLACER.step + 1e-9);
  const xSteps = Math.floor((xMax - left) / PLACER.step + 1e-9);
  for (let iy = 0; iy <= ySteps; iy++) {
    const y = yFrom - iy * PLACER.step;
    for (let ix = 0; ix <= xSteps; ix++) {
      const x = left + ix * PLACER.step;
      const candidate = expand({ left: x, right: x + w, bottom: y, top: y + h }, clear);
      if (!blockedRects.some((b) => overlaps(candidate, b))) {
        return { left: x, right: x + w, bottom: y, top: y + h };
      }
    }
  }
  return null;
}

/** Placement helper used by the component modules. */
export function pos(regionId: RegionId, ref: string): { pcbX: number; pcbY: number } {
  const fixed = FIXED_PLACEMENTS[ref];
  if (fixed) return fixed;
  return placeInRegion(regionId, ref);
}

export const at = pos;

function round2(n: number) {
  return Math.round(n * 100) / 100;
}
