# tscircuit hardware workspace

This directory is the authoritative source for the DCF77 receiver schematic and PCB design intent.

Rev.0 has **one board only**:

```text
Raspberry Pi Standard HAT+
```

The former standalone USB-C board, Type-C power block and standalone 3.3 V buck are removed from the reference design.

## Rev.0 hardware decisions

```text
Antenna      TDK B82453C0275A000, X winding
Antenna C    560 pF + 22 pF C0G/NP0, fixed
Antenna R    330 kOhm damping, fixed
Input buffer OPA810IDBVR
BPF          LTC1562IG#PBF, fixed 77.5 kHz / ~7.75 kHz
PGA          LTC6912IGN-1#PBF, gains 1/2/5/10/20/50/100
ADC driver   OPA2835IDGSR candidate pending final validation
ADC          LTC1407AIMSE-1#PBF @ 930 kS/s
TCXO         SiT5356AI-FQ-33E0-25.000000, 25 MHz, 3.3 V, ±100 ppb
FPGA         LFE5U-45F-7BG256I
SPI flash    W25Q64JVSSIQ, 64 Mbit, SOIC-8
Display      NHD-C0220BIZ-FSW-FBW-3V3M, 20x2 I2C FSTN LCD
PPS          mandatory dedicated ECP5 hardware output
UART         115200 8N1 date/time/status telemetry to Raspberry Pi

HAT 5V path  TPS22975NDSGR
HAT 3V3_D    direct PI_3V3 through current-measure link
Core buck    TPS628502DRLR -> 1V1_CORE
ADC LDO      LT3042EMSE#PBF -> 3V3_ADC_A
Clock LDO    TPS7A2033PDQNR -> 3V3_CLK
Aux LDO      TPS7A2025PDQNR -> 2V5_AUX
```

Reference analog and power hardware is intentionally **no-trim/no-selection**.

The physical ECP5-45F provides development headroom, but `release_reference` RTL must satisfy the historical XC3S1400AN limits in `rtl/resource_budget.json`.

## Machine-readable design plans

```text
hardware/tscircuit/pin-plan.json
hardware/tscircuit/power-plan.json
```

`pin-plan.json` defines ECP5 balls, bank assignments, Raspberry Pi GPIO mapping and the fixed UART electrical/protocol policy.

`power-plan.json` defines the HAT-only rail sources, regulator OPNs, passives, switching policy, sequencing and ECP5 decoupling.

The eventual TSX wrappers and FPGA constraints must be checked against these files.

## ECP5 VCCIO / bank plan

All populated ECP5 I/O banks use:

```text
3V3_D = PI_3V3
```

Bank roles:

```text
Bank 0  spare / future low-rate control
Bank 1  SiT5356 TCXO + Raspberry Pi SPI/UART/PPS host
Bank 2  LTC1407A ADC + LTC6912 control
Bank 3  reference PPS + LCD + diagnostics
Bank 6  reserved/quiet near AFE
Bank 7  reserved/quiet near AFE
Bank 8  SPI flash + sysCONFIG + JTAG
```

### Common signal balls

```text
CLK_25M      C9    GR_PCLK1_1
ADC_SCK      J16
ADC_SDO      J15
ADC_CONV     K16
PGA_SCK      H12
PGA_MOSI     H13
PGA_CS_N     J12
PPS_REF      R12
LCD_SCL      M13
LCD_SDA      N14
LCD_RST_N    M14
LCD_BL_EN    R13
```

### HAT+ host GPIO mapping

```text
Pi physical 19 / GPIO10 MOSI -> ECP5 A10
Pi physical 21 / GPIO9  MISO <- ECP5 D11
Pi physical 23 / GPIO11 SCLK -> ECP5 A9
Pi physical 24 / GPIO8  CE0  -> ECP5 E11
Pi physical 22 / GPIO25 IRQ  <- ECP5 C12
Pi physical 18 / GPIO24 RSTn -> ECP5 B12
Pi physical 7  / GPIO4  PPS  <- ECP5 A11

Pi physical 10 / GPIO15 RXD  <- ECP5 A13 / PT83A   [HAT_UART_TX]
Pi physical 8  / GPIO14 TXD  -> ECP5 A14 / PT83B   [HAT_UART_RX]
```

UART reference electrical population:

```text
33 ohm source-series resistor on each line
47 kOhm pull-up to 3V3_D on each line
115200 baud, 8N1, no flow control
```

Normal date/time transmission is once per second and is scheduled in the approximately `993...999 ms` tail after the DCF77 PM sequence. Keep the reference frame at or below 64 bytes.

`A12 / PT71B` remains spare between the HAT PPS pair and UART pair.

`ID_SD` and `ID_SC` on physical pins 27/28 connect only to the HAT+ ID EEPROM.

### Bank-8 boot balls

```text
MOSI       T8
MISO       T7
CSSPIN     N8
MCLK       N9
PROGRAMN   R9
INITN      T9
DONE       P9
CFG0       N10
CFG1       P10
CFG2       R10
TDO        M10
TCK        T10
TDI        R11
TMS        T11
```

## HAT-only power implementation

```text
PI_5V
  -> TPS22975NDSGR
  -> 5V_SYS
       +--> 0.10 ohm -> 5V_AFE
       +--> LT3042 -> 3V3_ADC_A
       +--> TPS7A2033 -> 3V3_CLK
       +--> TPS628502 -> 1V1_CORE
       +--> LCD backlight

PI_3V3
  -> current-measure / 0R
  -> 3V3_D
       +--> ECP5 VCCIO / flash / HAT EEPROM / LCD logic
       +--> TPS7A2025 -> 2V5_AUX
```

The 1.1 V TPS628502 uses:

```text
L       = DFE252012PD-R47M=P2, 0.47 uH
FSET    = 5.76 kOhm -> ~3.125 MHz nominal
SSC     = off
MODE    = forced PWM
CIN     = 10 uF + 100 nF
COUT    = 2 x 10 uF
feedback = 39.2 k / 47.0 k / 10 pF
```

The 2.25 MHz default is deliberately avoided because `29 * 77.5 kHz = 2.2475 MHz`.

## HAT sequencing

```text
PI_3V3
 -> 3V3_D / VCCIO8 / W25Q64 / 2V5_AUX
 -> enable TPS22975N
 -> 5V_SYS
 -> 1V1_CORE + analog/ADC/clock rails
```

When Pi 3.3 V disappears in HAT+ STANDBY, the HAT local 5 V path is disabled and no Pi-facing domain is back-powered.

ECP5 internal POR remains responsible for normal release after `VCC`, `VCCAUX` and `VCCIO8` are valid.

## Display

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 FSTN transflective
3.3 V I2C
```

LCD logic uses `3V3_D`; backlight uses `5V_SYS` and is normally OFF during precision RF measurements.

## CAD / layout workflow

```text
tscircuit
  -> Circuit JSON / KiCad export
  -> HAT+ RF/mechanical constraints
  -> Quilter placement/routing
  -> native KiCad review
  -> ERC/DRC + RF/EMI inspection
  -> fabrication
```

Quilter may not freely place/reroute:

- ferrite / tuning / OPA810 cluster;
- LTC1562 programming network;
- ADC/LT3042/OPA2835 cluster;
- TCXO/TPS7A2033/clock escape to `C9`;
- ECP5/flash Bank-8 boot cluster;
- external PPS path from `R12`;
- TPS628502 core hot loop;
- 5V_AFE branch entrance;
- Raspberry Pi header, UART, LCD, holes and other mechanical constraints.

No fast digital trace or switch node may run beneath or beside the ferrite/input network. SPI and UART routing stays in the HAT/digital region.

## Source tree

```text
hardware/tscircuit/
  pin-plan.json              ECP5 BG256 ball identity + Pi GPIO/UART mapping (safety-critical)
  power-plan.json            HAT-only rails, sequencing, ECP5 decoupling
  package.json               pinned tscircuit / tsx versions
  tsconfig.json
  tscircuit.config.json      build.routingDisabled = true (pre-Quilter: no routing here)
  src/
    index.tsx                board root: constraints + region annotations
    core/
      receiver_core.tsx
      afe.tsx                ferrite + OPA810 + LTC1562 + LTC6912 + LTC1407A
      adc.tsx
      ecp5.tsx               LFE5U-45F-7BG256I + W25Q64JV config flash
      clock.tsx              SiT5356 25 MHz TCXO
      pps.tsx
      display.tsx            LCD 20x2 transflective I2C
      receiver_power.tsx
    board/
      raspberry_pi_hatplus.tsx
      host_esd.tsx           HAT+/test-interface ESD freeze
      hatplus_constraints.ts locked placements, regions, courtyards, placer
      quilter.ts             Quilter handoff manifest + keepouts
    host/
      rpi_spi.tsx
    power/
      hat_5v_input.tsx
    parts/
      footprints.tsx         audited JLCPCB 0402 R/C land patterns + supplier pinning
  lattice/
    bg256-identity.json      committed derivation from FPGA-SC-02034 (pad/ball/function/bank)
  suppliers/
    jlcpcb-land-patterns.json  audited JLCPCB 0402 R/C copper geometry (part list + pads)
  scripts/
    verify-bga-identity.ts   BGA256 ball-identity gate (fails on renumbering)
    import-lattice-pinout.ts folds a Lattice FPGA-SC-02034 export into pin-plan.json
    validate-design-plans.ts pin plan + power plan + placement regions gate
    verify-footprints.ts     supplier land-pattern gate (offline, reads the export)
    audit-supplier-footprints.ts re-fetch the EasyEDA land patterns (network)
    check-erc.ts             ERC/DRC gate over the four `tsci check` passes
    measure-courtyards.ts    re-calibrates SIZE_MM from rendered footprints
    export-quilter-manifest.ts
    archive-revision.ts
  dist/
    REVISION.json            git SHA + pinned toolchain + artifact checksums
    circuit-json/            dcf77-hat.circuit.json, placement-regions.json, board-rules.json
    kicad-pre-quilter/       dcf77-hat.zip (gitignored, reproducible)
    kicad-post-quilter/      filled in after a reviewed Quilter run
    fabrication/             Gerbers/BOM/PnP after a reviewed Quilter run
```

Platform RTL now also includes:

```text
rtl/platform/uart_tx.sv
```

The byte-level UART transmitter is intentionally separate from the future date/time formatter so calendar decoding remains owned by the receiver core.

## Reproducing and verifying

```bash
npm ci                            # bun is required by the tsci CLI shebang: put ~/.bun/bin on PATH
npx tsci build src/index.tsx      # AC1: writes dist/src/index/circuit.json
npm run export:circuit            # dist/circuit-json/dcf77-hat.circuit.json
npm run export:kicad              # dist/kicad-pre-quilter/dcf77-hat.zip
npm run manifest                  # placement-regions.json + board-rules.json
npm run check                     # pin/power plan + placement regions + BGA identity
npm run check:bga:release         # strict gate: blocks fabrication while the ball audit is incomplete
npm run check:footprints          # audited supplier land patterns (needs export:circuit)
npm run check:erc                 # ERC + netlist + shorts + placement DRC
npm run audit:footprints          # re-fetch the JLCPCB land patterns (network, manual)
npm run archive                   # dist/REVISION.json (run after the source commit)
```

Pre-routing ERC/DRC + PDN (item "run ERC/DRC and PDN/power-estimator checks before routing").
The four ERC/DRC passes are wrapped by `npm run check:erc`, which exits non-zero unless
source/netlist/shorts are clean and placement has 0 errors with no warning other than the two
mechanically-fixed connector orientation notices:

```bash
npm run check:erc                        # gate over the four passes below
npx tsci check source src/index.tsx      # ERC: 0 errors, 0 warnings
npx tsci check netlist src/index.tsx     # connectivity: every net resolves
npx tsci check shorts src/index.tsx      # no unintended copper shorts
npx tsci check placement src/index.tsx   # placement DRC: 0 errors (2 known connector warnings)
```

Results at this revision: source 0/0, netlist 0/0, shorts none, placement 0 errors with two
pre-existing informational `pcb_connector_not_in_accessible_orientation_warning` entries for
`J1` (the HAT+ 40-pin header, whose orientation is fixed by the HAT+ mechanical spec) and
`J2` (the JTAG recovery header, reachable from the board edge per the `ecp5_flash` region
rule). `tsci check placement` treats any warning as a non-zero exit, so the two are allow-listed
explicitly in `scripts/check-erc.ts` rather than masked. The `1V1_CORE` buck switch node, the
AFE clusters and the TCXO remain outside every host/ESD part.
`scripts/measure-courtyards.ts --check` also passes (146 rendered components, all region
members declared >= measured).

There is still no dedicated PDN/power-estimator script in this workspace. The available
substitute is the `power-plan.json` <-> `rail_*` net cross-check run by `npm run check:plans`,
which currently matches 7 derived rails + 2 HAT input rails 1:1 and confirms every declared
rail has a live schematic net (and vice versa). A first-order current/IR model would need the
per-rail load currents, which `power-plan.json` only carries for `5V_AFE` (75 mA); the other
rails stay open until the ECP5 power estimator is run post-synthesis.

`routingDisabled` in `tscircuit.config.json` is deliberate: this workspace stops at the
pre-Quilter handoff, so unrouted `pcb_port_not_connected_error` entries are not defects here.
Quilter (or the manual KiCad pass) owns routing.

### ECP5 ball-identity audit status

`pin-plan.json` carries all 256 BG256 balls and a frozen SHA-256 over the ball identity.
**All 256/256 balls are now cross-checked against Lattice `FPGA-SC-02034` Rev 3.0
(ECP5U-45 Pinout, caBGA256 column)**, so `npm run check:bga` and
`npm run check:bga:release` both pass on the committed source and fabrication is no
longer blocked by the ball audit.

The raw Lattice export is not vendored; `pin-plan.json -> ball_audit.source` records the
document, revision and SHA-256 of the download, and `lattice/bg256-identity.json` holds the
committed derivation (pad, ball, function, bank) that
`scripts/import-lattice-pinout.ts` produced from it. Re-running the cross-check against a
freshly downloaded export needs no importer round-trip:

```bash
npm run check:bga:release -- --lattice <FPGA-SC-02034-*.csv>   # function + bank, ball by ball
```

Any export that renumbers or reorders the ball names, or that changes a pin function, still
fails the gate. To fold a new export into the source of truth:

```bash
tsx scripts/import-lattice-pinout.ts --lattice <FPGA-SC-02034-*.csv> --write
```

## Schematic-freeze status (Rev.0)

No schematic-freeze work is outstanding at this revision. The remaining work listed in the
BEA-42 ticket is closed; the only item that stays open is genuinely downstream of layout
(post-Quilter Gerbers/BOM/PnP) and is tracked outside this workspace.

### Supplier land patterns

Every 0402 passive is pinned to an explicit JLCPCB part and declares the audited JLCPCB land
pattern instead of the generic tscircuit `0402` footprinter. The generic copper bbox
(1.56 x 0.64 mm) missed the supplier packages, so `tscircuit` emitted 69
`supplier_footprint_mismatch_warning` entries (copper IoU 0.7741 for resistors, 0.7249 for
capacitors, against a 0.80 threshold).

```text
R0402  copper bbox 1.4313 x 0.5400 mm, pads 0.565658 x 0.540004 mm @ pitch 0.865632 mm
C0402  copper bbox 1.3402 x 0.5400 mm, pads 0.500000 x 0.540004 mm @ pitch 0.840232 mm
```

- geometry: `suppliers/jlcpcb-land-patterns.json` (part list, package, copper bbox, pads);
- source: EasyEDA component API, retrieved 2026-09-11, unit 0.254 mm;
- re-audit: `npm run audit:footprints` (network; `--write` refreshes the JSON);
- offline gate: `npm run check:footprints` re-derives each pinned passive's copper bbox from
  the exported Circuit JSON and fails on any surviving `supplier_footprint_mismatch_warning`;
- one pinned part (`RFSET` -> `C5153969`, FRC0402F5761TS) has no EasyEDA package, so it is not
  in the audit set; it keeps the standard R0402 land pattern.

`CVIOBANK`'s declared courtyard was also re-measured (1.65 -> 1.70 mm) so
`scripts/measure-courtyards.ts --check` is clean.

### Closed in this revision

- 256/256 BG256 ball identities verified against Lattice `FPGA-SC-02034`;
- 69/69 `supplier_footprint_mismatch_warning` resolved with audited JLCPCB land patterns
  (`src/parts/footprints.tsx`, `suppliers/jlcpcb-land-patterns.json`);
- UART 33 ohm series + 47 kOhm idle-high networks physically wired (`src/host/rpi_spi.tsx`);
- LCD backlight final values fixed: RBL1 = 68 ohm, RBL2 = 10 kOhm, RBL3 = 100 kOhm
  pull-down, LCD_BLQ = BSS138 (`src/core/display.tsx`);
- HAT+/test-interface ESD freeze: `src/board/host_esd.tsx`;
- ERC/DRC + footprint gates wired and passing (`npm run check:erc`, `npm run check:footprints`).

Supporting docs:

- `docs/17-pcb-variants.md` — single HAT+ board architecture;
- `docs/19-power-tree.md` — HAT power tree;
- `docs/23-ecp5-boot-config.md` — ECP5 boot/JTAG;
- `docs/26-hat-power.md` — Pi rail split;
- `docs/27-ecp5-pin-plan-hat.md` — pin planning;
- `docs/28-power-passives-sequencing.md` — exact power values;
- `docs/29-hat-uart-time.md` — UART date/time/status telemetry.
