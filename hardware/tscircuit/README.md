# tscircuit hardware workspace

This directory is the authoritative source for DCF77 receiver schematic and PCB design intent.

The project produces two PCB variants from one shared receiver core:

1. Raspberry Pi Standard HAT+;
2. standalone USB-C receiver.

## Rev.0 hardware decisions

```text
Antenna      TDK B82453C0275A000, X winding
Antenna C    560 pF + 22 pF C0G/NP0, fixed
Antenna R    330 kOhm damping, fixed
Input buffer OPA810IDBVR
BPF          LTC1562IG#PBF, fixed 77.5 kHz / ~7.75 kHz
PGA          LTC6912IGN-1#PBF, gains 1/2/5/10/20/50/100
ADC driver   OPA2835IDGSR candidate pending validation
ADC          LTC1407AIMSE-1#PBF @ 930 kS/s
TCXO         SiT5356AI-FQ-33E0-25.000000, 25 MHz, 3.3 V, ±100 ppb
FPGA         LFE5U-45F-7BG256I
SPI flash    W25Q64JVSSIQ, 64 Mbit, SOIC-8
Display      NHD-C0220BIZ-FSW-FBW-3V3M, 20x2 I2C FSTN LCD
PPS          mandatory dedicated ECP5 hardware output

Core buck    TPS628502DRLR -> 1V1_CORE
ADC LDO      LT3042EMSE#PBF -> 3V3_ADC_A
Clock LDO    TPS7A2033PDQNR -> 3V3_CLK
Aux LDO      TPS7A2025PDQNR -> 2V5_AUX

Standalone 3V3_D:
             TPS628502DRLR
USB-C:       USB4105-GF-A / TUSB320LAIRWBR / TPS259470ARPWR

HAT 5V path: TPS22975NDSGR
HAT 3V3_D:   direct PI_3V3 through current-measure link
```

Reference analog and power hardware is intentionally **no-trim/no-selection**. Production boards must not require hand-selected antenna/filter/power R/C values.

The physical ECP5-45F provides development headroom, but `release_reference` RTL must satisfy the historical XC3S1400AN limits in `rtl/resource_budget.json`.

## Machine-readable design plans

Two machine-readable inputs are now frozen:

```text
hardware/tscircuit/pin-plan.json
hardware/tscircuit/power-plan.json
```

`pin-plan.json` defines ECP5 balls, bank assignments and Raspberry Pi GPIO mapping.

`power-plan.json` defines rail sources by variant, regulator OPNs, fixed regulator passives, switcher policy, HAT power switching, sequencing and ECP5 decoupling.

The eventual TSX wrappers and generated FPGA constraints must be checked against these files so implementation cannot silently diverge from the reviewed plans.

Human-readable references:

```text
docs/27-ecp5-pin-plan-hat.md
docs/28-power-passives-sequencing.md
```

## ECP5 VCCIO / bank plan

All populated ECP5 user-I/O banks use `3V3_D`:

```text
Bank 0  spare / standalone low-rate control
Bank 1  SiT5356 TCXO + Raspberry Pi HAT+ host
Bank 2  LTC1407A ADC + LTC6912 control
Bank 3  reference PPS + LCD + diagnostics
Bank 6  reserved/quiet near AFE
Bank 7  reserved/quiet near AFE
Bank 8  SPI flash + sysCONFIG + JTAG
```

Source of `3V3_D`:

```text
standalone: 5V_SYS -> TPS628502 -> 3V3_D
HAT+:       PI_3V3 -------------> 3V3_D
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

## Frozen power implementation

### Fixed AFE branch

```text
5V_SYS -> 0.10 ohm, 1% -> 5V_AFE
5V_AFE -> 100 uF + 1 uF + 100 nF to GND
```

No ferrite-bead or resistor-value selection is part of the reference BOM.

### TPS628502 common implementation

```text
TPS628502DRLR
L       = DFE252012PD-R47M=P2, 0.47 uH
FSET    = 5.76 kOhm -> ~3.125 MHz nominal
SSC     = off
MODE    = forced PWM
CIN     = 10 uF + 100 nF
COUT    = 2 x 10 uF
```

The internal 2.25 MHz default is not used; `29 * 77.5 kHz = 2.2475 MHz`, an unattractive nominal relationship for a weak-signal DCF77 receiver.

Core feedback:

```text
39.2 k / 47.0 k / 10 pF -> ~1.100 V
```

Standalone 3V3_D feedback:

```text
88.7 k / 19.6 k / 10 pF -> ~3.316 V
```

### ADC rail

```text
LT3042EMSE#PBF
RSET 33.2 k
CSET 4.7 uF
CIN  10 uF
COUT 10 uF
```

### Clock rail

```text
TPS7A2033PDQNR
CIN/COUT = 2.2 uF
100 nF local at SiT5356
```

### ECP5 auxiliary rail

```text
TPS7A2025PDQNR
input = 3V3_D
CIN/COUT = 2.2 uF
```

### HAT input

```text
PI_5V -> TPS22975NDSGR -> 5V_SYS
ON = PI_3V3 with 100 k pulldown
CT = 1.0 nF >=30 V

PI_3V3 -> current-measure/0R -> 3V3_D
```

## Variant sequencing

Standalone:

```text
5V_SYS
 -> 3V3_D / VCCIO8 / W25Q64
 -> 2V5_AUX
 -> PG_3V3_D enables 1V1_CORE
```

HAT+:

```text
PI_3V3
 -> 3V3_D / VCCIO8 / W25Q64 / 2V5_AUX
 -> enable TPS22975N
 -> 5V_SYS
 -> 1V1_CORE + analog/ADC/clock rails
```

ECP5 internal POR remains responsible for release from reset after `VCC`, `VCCAUX` and `VCCIO8` are valid. `PROGRAMN` remains available for manual/open-drain reconfiguration; no arbitrary-delay analog supervisor is added solely for normal boot.

## Display

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 FSTN transflective
3.3 V I2C
```

LCD logic uses `3V3_D`. Backlight is separately switched and normally OFF during precision RF measurements. On HAT+, backlight current comes from `5V_SYS`, not `PI_3V3`.

## CAD / layout workflow

```text
tscircuit
  -> Circuit JSON / KiCad export
  -> hard RF/mechanical constraints
  -> Quilter placement/routing
  -> native KiCad review
  -> ERC/DRC + RF/EMI inspection
  -> fabrication
```

Quilter is not allowed to freely place/reroute:

- ferrite / tuning / OPA810 cluster;
- LTC1562 programming network;
- ADC/LT3042/OPA2835 cluster;
- TCXO/TPS7A2033/clock escape to ECP5 `C9`;
- ECP5/flash Bank-8 boot cluster;
- external PPS path from `R12`;
- TPS628502 hot loops/inductors;
- 5V_AFE branch entrance/filter;
- mechanically fixed LCD/connectors/holes.

No fast digital trace or switch node may run beneath or beside the ferrite/input network.

## Planned source tree

```text
hardware/tscircuit/
  pin-plan.json
  power-plan.json
  package.json
  tsconfig.json
  src/
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      display.tsx
      pps.tsx
      receiver_power.tsx
    variants/
      raspberry_pi_hatplus.tsx
      standalone_usb_c.tsx
    host/
      rpi_spi.tsx
      usb_debug.tsx
    power/
      hat_5v_input.tsx
      usb_c_5v_input.tsx
    parts/
    board/
      common_constraints.ts
      hatplus_constraints.ts
      standalone_constraints.ts
      quilter.ts
```

## Remaining schematic-freeze work

Pin mapping and power passive selection are no longer open. Remaining work is now implementation-level:

- create verified tscircuit part wrappers/footprints from manufacturer pinouts;
- calculate final LCD backlight current resistor/MOSFET values;
- freeze ESD/TVS and connector-shield components;
- decide whether standalone Rev.0 populates USB 2.0 data hardware;
- generate the first complete pin-accurate common-core TSX;
- run ERC/DRC and PDN/power-estimator checks before routing.
