# tscircuit hardware workspace

This directory is the authoritative source for the DCF77 receiver schematic and PCB design intent.

Rev.0 now has **one board only**:

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

`pin-plan.json` defines ECP5 balls, bank assignments and Raspberry Pi GPIO mapping.

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
Bank 1  SiT5356 TCXO + Raspberry Pi HAT+ host
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
```

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
- Raspberry Pi header, LCD, holes and other mechanical constraints.

No fast digital trace or switch node may run beneath or beside the ferrite/input network.

## Planned source tree

```text
hardware/tscircuit/
  pin-plan.json
  power-plan.json
  package.json
  tsconfig.json
  src/
    index.tsx
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      display.tsx
      pps.tsx
      receiver_power.tsx
    board/
      raspberry_pi_hatplus.tsx
      hatplus_constraints.ts
      quilter.ts
    host/
      rpi_spi.tsx
    power/
      hat_5v_input.tsx
    parts/
  scripts/
```

## Remaining schematic-freeze work

- create verified tscircuit part wrappers/footprints from manufacturer pinouts;
- validate BGA256 pad identity through KiCad export;
- calculate final LCD backlight current resistor/MOSFET values;
- freeze HAT connector ESD/protection where needed;
- generate the first complete pin-accurate HAT TSX;
- run ERC/DRC and PDN/power-estimator checks before routing.

Supporting docs:

- `docs/17-pcb-variants.md` — single HAT+ board architecture;
- `docs/19-power-tree.md` — HAT power tree;
- `docs/23-ecp5-boot-config.md` — ECP5 boot/JTAG;
- `docs/26-hat-power.md` — Pi rail split;
- `docs/27-ecp5-pin-plan-hat.md` — pin planning;
- `docs/28-power-passives-sequencing.md` — exact power values.
