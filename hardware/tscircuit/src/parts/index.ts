/**
 * Component catalogue for Rev.0.
 *
 * Every OPN and value here is taken verbatim from the frozen hardware decisions
 * (hardware/tscircuit/README.md "Rev.0 hardware decisions", docs/19, 20, 21, 22,
 * 23, 24, 26, 28). No value is invented here; reconstruction choices are marked.
 *
 * PINOUT STATUS
 * -------------
 * The ECP5 ball identity is audited (pin-plan.json). The other ICs are modelled
 * with their documented functional pin names on a package-appropriate footprint;
 * the pad-number-to-pin-name mapping for those parts still has to be verified
 * against each manufacturer pinout before the schematic is frozen. This is listed
 * as remaining work in hardware/tscircuit/README.md ("create verified tscircuit
 * part wrappers/footprints from manufacturer pinouts").
 */
import { LOCKED_PLACEMENTS, pos, type RegionId } from "../board/hatplus_constraints";

export const PARTS = {
  antenna: { opn: "TDK B82453C0275A000", note: "3D ferrite transponder coil, X winding only; Y/Z open" },
  antennaCap560: { opn: "560 pF C0G/NP0 1%", note: "CANT1" },
  antennaCap22: { opn: "22 pF C0G/NP0 1%", note: "CANT2" },
  antennaDamp: { opn: "330 kOhm thin-film 1%", note: "RANT" },
  buffer: { opn: "OPA810IDBVR", note: "SOT-23-5, FET input, RRIO, 5 V" },
  bpf: { opn: "LTC1562IG#PBF", note: "20-pin SSOP, fixed 77.5 kHz / 7.75 kHz BW / gain 10" },
  pga: { opn: "LTC6912IGN-1#PBF", note: "16-pin SSOP, gains 0/1/2/5/10/20/50/100" },
  adcDriver: { opn: "OPA2835IDGSR", note: "candidate pending final validation" },
  adc: { opn: "LTC1407AIMSE-1#PBF", note: "14-bit, 930 kS/s = 12 x 77.5 kHz, MSOP-10" },
  ecp5: { opn: "LFE5U-45F-7BG256I", note: "BG256 caBGA 14x14 mm, 0.8 mm pitch" },
  flash: { opn: "W25Q64JVSSIQ", note: "64 Mbit SPI NOR, SOIC-8 208 mil" },
  tcxo: { opn: "SiT5356AI-FQ-33E0-25.000000", note: "25 MHz, 3.3 V, ±100 ppb" },
  lcd: { opn: "NHD-C0220BIZ-FSW-FBW-3V3M", note: "20x2 FSTN transflective, I2C, ST7036" },
  loadSwitch: { opn: "TPS22975NDSGR", note: "HAT 5 V load switch, ~16 mOhm RON" },
  coreBuck: { opn: "TPS628502DRLR", note: "1V1_CORE, forced PWM ~3.125 MHz" },
  coreInductor: { opn: "DFE252012PD-R47M=P2", note: "0.47 uH shielded" },
  adcLdo: { opn: "LT3042EMSE#PBF", note: "3V3_ADC_A, RSET 33.2 kOhm" },
  clockLdo: { opn: "TPS7A2033PDQNR", note: "3V3_CLK" },
  auxLdo: { opn: "TPS7A2025PDQNR", note: "2V5_AUX from 3V3_D" },
  idEeprom: { opn: "CAT24C32-compatible", note: "HAT+ ID EEPROM at 0x50" },
} as const;

/** Placement helper: a component inside its constrained region. */
export const at = (region: RegionId, ref: string) => pos(region, ref);

/** Placement helper: a locked (Quilter must not move) component. */
export const lockedAt = (ref: string) => {
  const p = LOCKED_PLACEMENTS[ref];
  if (!p) throw new Error(`"${ref}" has no locked placement in hatplus_constraints.ts`);
  return { pcbX: p.x, pcbY: p.y, pcbRotation: p.rotation ?? 0 };
};

/** Passive footprint by value class, so values stay readable at the callsite. */
export const FP = {
  r0402: "0402",
  r0603: "0603",
  r0805: "0805",
  c0402: "0402",
  c0603: "0603",
  c0805: "0805",
  soic8: "soic8",
  msop10: "msop10",
  sot235: "sot23-5",
  ssop16: "ssop16",
  ssop20: "ssop20",
  sot236: "sot23-6",
  sot583: "sot563",
  dfn10: "dfn10",
  sit4: "dfn4",
  bga256: "bga256",
  pinheader40: "pinheader40",
  pinheader4: "pinheader4",
  connector4: "pinheader4",
} as const;
