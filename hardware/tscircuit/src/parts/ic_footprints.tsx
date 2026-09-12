/**
 * Audited IC land patterns for the parts whose frozen package is NOT the generic
 * footprinter shape.
 *
 * Each footprint below is transcribed from the manufacturer's *recommended*
 * land pattern (or, where the manufacturer publishes only a package outline, from
 * that outline plus the published solder-print figure), not from a generic
 * "10-pin DFN" guess. That distinction matters: the previous Rev.0 model put the
 * LTC1407A, the LT3042, the SiT5356 and the TPS628502 on generically-named pads
 * with the wrong pad count, and `footprint="msop10"` / `"dfn4"` / `"sot563"`
 * silently renumbered them.
 *
 * Provenance per footprint (see also hardware/tscircuit/ic-pinouts.json):
 *   MSOP-10-1EP   LTC DWG 05-08-1664 Rev I/C "MSOP (MSE) / RECOMMENDED SOLDER PAD
 *                 LAYOUT" — used by both LT3042EMSE#PBF and LTC1407AIMSE-1#PBF.
 *   X2SON-4-1EP   TI 4215302/E (DQN0004A) "EXAMPLE BOARD LAYOUT".
 *   SOT-583-8     TI 4224486/G (DRL0008A) "EXAMPLE BOARD LAYOUT".
 *   TCXO-5032-10  SiTime "Package Outline PQD-CQFN-10-050302-036" (body 5.000 x
 *                 3.200 mm, 10L CQFN) + "Solder Print Layout SPL-001-RevA"
 *                 (overall land 4.050 x 2.350 mm, side-pad width 0.700 mm).
 *   LCD-8PIN-2BL  Newhaven "Recommended PCB Footprint" for NHD-C0220BiZ
 *                 (8 interface pads, P2.0*7 = 14 mm, 0.5 x 0.3 mm; plus the
 *                 separate 2-pin backlight connector).
 *
 * The courtyard rectangles are the ones the pre-Quilter placer measures
 * (scripts/measure-courtyards.ts); they follow the datasheet courtyard.
 */

// ---------------------------------------------------------------------------
// MSOP-10 + exposed pad (LTC "MSE" package, 05-08-1664)
// ---------------------------------------------------------------------------
/** 10-lead MSOP 3x3 mm, 0.5 mm pitch, exposed GND pad 1.68 x 1.88 mm. */
export const FP_MSOP10_EP = (
  <footprint>
    <smtpad portHints={["pin1"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={-2.15} pcbY={1.0} />
    <smtpad portHints={["pin2"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={-2.15} pcbY={0.5} />
    <smtpad portHints={["pin3"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={-2.15} pcbY={0.0} />
    <smtpad portHints={["pin4"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={-2.15} pcbY={-0.5} />
    <smtpad portHints={["pin5"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={-2.15} pcbY={-1.0} />
    <smtpad portHints={["pin6"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={2.15} pcbY={-1.0} />
    <smtpad portHints={["pin7"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={2.15} pcbY={-0.5} />
    <smtpad portHints={["pin8"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={2.15} pcbY={0.0} />
    <smtpad portHints={["pin9"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={2.15} pcbY={0.5} />
    <smtpad portHints={["pin10"]} shape="rect" width="1.45mm" height="0.30mm" pcbX={2.15} pcbY={1.0} />
    <smtpad portHints={["pin11"]} shape="rect" width="1.68mm" height="1.88mm" pcbX={0} pcbY={0} />
    <courtyardrect width="6.26mm" height="3.50mm" />
  </footprint>
);

// ---------------------------------------------------------------------------
// X2SON-4 + exposed thermal pad (TI DQN0004A, 1 x 1 mm)
// ---------------------------------------------------------------------------
/** 4-pin X2SON 1 x 1 mm, 0.65 mm pitch, thermal pad 0.48 x 0.38 mm. */
export const FP_X2SON4_EP = (
  <footprint>
    <smtpad portHints={["pin1"]} shape="rect" width="0.21mm" height="0.36mm" pcbX={-0.43} pcbY={0.325} />
    <smtpad portHints={["pin2"]} shape="rect" width="0.21mm" height="0.36mm" pcbX={-0.43} pcbY={-0.325} />
    <smtpad portHints={["pin3"]} shape="rect" width="0.21mm" height="0.36mm" pcbX={0.43} pcbY={-0.325} />
    <smtpad portHints={["pin4"]} shape="rect" width="0.21mm" height="0.36mm" pcbX={0.43} pcbY={0.325} />
    <smtpad portHints={["pin5"]} shape="rect" width="0.48mm" height="0.38mm" pcbX={0} pcbY={0} />
    <courtyardrect width="1.30mm" height="1.30mm" />
  </footprint>
);

// ---------------------------------------------------------------------------
// SOT-583 8-lead (TI DRL0008A, 1.60 x 2.10 mm)
// ---------------------------------------------------------------------------
/** 8-pin SOT-583, 0.5 mm pitch, 4 pads per side. */
export const FP_SOT583_8 = (
  <footprint>
    <smtpad portHints={["pin1"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={-0.74} pcbY={0.75} />
    <smtpad portHints={["pin2"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={-0.74} pcbY={0.25} />
    <smtpad portHints={["pin3"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={-0.74} pcbY={-0.25} />
    <smtpad portHints={["pin4"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={-0.74} pcbY={-0.75} />
    <smtpad portHints={["pin5"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={0.74} pcbY={-0.75} />
    <smtpad portHints={["pin6"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={0.74} pcbY={-0.25} />
    <smtpad portHints={["pin7"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={0.74} pcbY={0.25} />
    <smtpad portHints={["pin8"]} shape="rect" width="0.67mm" height="0.30mm" pcbX={0.74} pcbY={0.75} />
    <courtyardrect width="2.15mm" height="2.05mm" />
  </footprint>
);

// ---------------------------------------------------------------------------
// SiTime 10L CQFN 5.0 x 3.2 mm (PQD-CQFN-10-050302-036 / SPL-001-RevA)
// ---------------------------------------------------------------------------
/**
 * 10-pad 5.0 x 3.2 mm SiTime package.
 *
 * Pad placement follows the datasheet bottom view: 9/10/1 along one long edge,
 * 6/5/4 along the other, and 8/7 (left) / 2/3 (right) on the two short edges.
 * The overall land is 4.050 x 2.350 mm with 0.700 mm side pads, as published in
 * the SiTime solder-print figure.
 */
export const FP_TCXO_5032_10 = (
  <footprint>
    <smtpad portHints={["pin9"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={-1.2} pcbY={1.0} />
    <smtpad portHints={["pin10"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={0} pcbY={1.0} />
    <smtpad portHints={["pin1"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={1.2} pcbY={1.0} />
    <smtpad portHints={["pin6"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={-1.2} pcbY={-1.0} />
    <smtpad portHints={["pin5"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={0} pcbY={-1.0} />
    <smtpad portHints={["pin4"]} shape="rect" width="1.05mm" height="0.35mm" pcbX={1.2} pcbY={-1.0} />
    <smtpad portHints={["pin8"]} shape="rect" width="0.70mm" height="0.70mm" pcbX={-1.675} pcbY={0.4} />
    <smtpad portHints={["pin7"]} shape="rect" width="0.70mm" height="0.70mm" pcbX={-1.675} pcbY={-0.4} />
    <smtpad portHints={["pin2"]} shape="rect" width="0.70mm" height="0.70mm" pcbX={1.675} pcbY={0.4} />
    <smtpad portHints={["pin3"]} shape="rect" width="0.70mm" height="0.70mm" pcbX={1.675} pcbY={-0.4} />
    <courtyardrect width="4.05mm" height="2.35mm" />
  </footprint>
);

// ---------------------------------------------------------------------------
// Newhaven NHD-C0220BiZ COG LCD pad set
// ---------------------------------------------------------------------------
/**
 * The module's board interface: eight I2C/interface pads on a 2.0 mm pitch row
 * (datasheet "P2.0*7 = 14", pad 0.5 x 0.3 mm). The backlight is a *separate*
 * two-pin connector on the module and is modelled as its own component, J4
 * (see FP_BL_2PIN below), exactly as the datasheet lists it.
 */
export const FP_LCD_8PIN = (
  <footprint>
    <smtpad portHints={["pin1"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={-7.0} pcbY={0} />
    <smtpad portHints={["pin2"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={-5.0} pcbY={0} />
    <smtpad portHints={["pin3"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={-3.0} pcbY={0} />
    <smtpad portHints={["pin4"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={-1.0} pcbY={0} />
    <smtpad portHints={["pin5"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={1.0} pcbY={0} />
    <smtpad portHints={["pin6"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={3.0} pcbY={0} />
    <smtpad portHints={["pin7"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={5.0} pcbY={0} />
    <smtpad portHints={["pin8"]} shape="rect" width="0.5mm" height="0.3mm" pcbX={7.0} pcbY={0} />
    <courtyardrect width="14.75mm" height="1.00mm" />
  </footprint>
);

/** The module's separate 2-pin backlight connector (LED anode / cathode). */
export const FP_BL_2PIN = (
  <footprint>
    <smtpad portHints={["pin1"]} shape="rect" width="0.6mm" height="0.6mm" pcbX={-1.0} pcbY={0} />
    <smtpad portHints={["pin2"]} shape="rect" width="0.6mm" height="0.6mm" pcbX={1.0} pcbY={0} />
    <courtyardrect width="3.10mm" height="1.10mm" />
  </footprint>
);
