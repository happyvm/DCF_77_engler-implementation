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

Standalone USB-C:
connector    GCT USB4105-GF-A
CC logic     TUSB320LAIRWBR, fixed UFP/sink
power path   TPS259470ARPWR eFuse
```

Reference analog hardware is intentionally no-trim. Production boards must not require hand-selected antenna/filter R/C values.

The physical ECP5-45F provides development headroom, but `release_reference` RTL must satisfy the historical XC3S1400AN limits in `rtl/resource_budget.json`.

## Machine-readable ECP5 pin plan

The Rev.0 FPGA/HAT assignment is frozen in:

```text
hardware/tscircuit/pin-plan.json
```

Human-readable rationale and Raspberry Pi physical-pin mapping:

```text
docs/27-ecp5-pin-plan-hat.md
```

### VCCIO policy

All populated ECP5 I/O banks use the same logical 3.3 V rail:

```text
VCCIO0/1/2/3/6/7/8 = 3V3_D
```

Source differs by board:

```text
standalone: 5V_SYS -> local buck -> 3V3_D
HAT+:       PI_3V3 -------------> 3V3_D
```

### Bank roles

```text
Bank 0  spare / standalone low-rate control
Bank 1  SiT5356 TCXO + Raspberry Pi HAT+ host interface
Bank 2  LTC1407A ADC + LTC6912 PGA control
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

`ID_SD` and `ID_SC` on physical pins 27/28 connect only to the HAT+ ID EEPROM and never to ECP5.

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

See [`../../docs/23-ecp5-boot-config.md`](../../docs/23-ecp5-boot-config.md).

## Variant power architecture

The precision/analog rails remain locally generated on both boards, but the digital 3.3 V source differs intentionally.

### Standalone USB-C

```text
USB-C 5 V -> protected 5V_SYS

5V_SYS
  +--> filtered 5V_AFE
  +--> LT3042 -> 3V3_ADC_A
  +--> TPS7A20 -> 3V3_CLK
  +--> TPS628502 -> 3V3_D
  +--> TPS628502 -> 1V1_CORE

3V3_D -> TPS7A20 -> 2V5_AUX
```

### Raspberry Pi HAT+

```text
PI_5V
  -> protected/gated 5V_SYS
       +--> filtered 5V_AFE
       +--> LT3042 -> 3V3_ADC_A
       +--> TPS7A20 -> 3V3_CLK
       +--> TPS628502 -> 1V1_CORE
       +--> LCD backlight path

PI_3V3
  -> current-measure / 0R link
  -> 3V3_D
       +--> all ECP5 VCCIO banks / VCCIO8
       +--> W25Q64JV
       +--> HAT ID EEPROM
       +--> LCD logic
       +--> PPS / Pi host-I/O domain
       +--> TPS7A20 -> 2V5_AUX under controlled enable
```

The HAT does not populate the standalone board's 3.3 V buck.

`PI_3V3` never powers ADC/OPA2835, TCXO, AFE, ECP5 core or LCD backlight.

See [`../../docs/26-hat-power.md`](../../docs/26-hat-power.md).

## HAT+ STANDBY policy

```text
PI_3V3 present -> 3V3_D valid -> enable 5V_SYS/local rails
PI_3V3 absent  -> 3V3_D off   -> disable 5V_SYS/local rails
```

No alternate source may back-power `3V3_D` while Pi 3.3 V is absent.

## FPGA boot/configuration

```text
LFE5U-45F-7BG256I
W25Q64JVSSIQ, 64 Mbit
Master SPI serial
CFG[2:0] = 010
```

JTAG is mandatory on both variants. `PROGRAMN`, `INITN` and `DONE` remain accessible.

## Display

Both variants use:

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2
FSTN transflective
3.3 V I2C
```

LCD logic uses `3V3_D`. Backlight is separately switched and normally OFF during precision RF measurements. On the HAT, backlight current comes from `5V_SYS`, not `PI_3V3`.

## Standalone USB-C

```text
USB4105-GF-A
  -> TUSB320LAIRWBR UFP/sink
  -> TPS259470ARPWR controlled power path
  -> 5V_SYS
```

No USB-PD is required. USB 2.0 D+/D- remain optional for a future debug/data path.

## CAD / layout workflow

```text
tscircuit
  -> KiCad export
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
- TCXO/clock escape to ECP5 `C9`;
- ECP5/flash Bank-8 boot cluster;
- external PPS path from `R12`;
- power-converter hot loops;
- mechanically fixed LCD/connectors/holes.

No fast digital trace or switch node may run beneath or beside the ferrite/input network.

## Planned source tree

```text
hardware/tscircuit/
  pin-plan.json
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

## Remaining schematic-freeze items

The pin plan and HAT GPIO allocation are no longer open. Remaining work:

- freeze regulator feedback/passives/decoupling from final power estimate;
- freeze HAT `PI_3V3` current/protection/decoupling implementation;
- decide whether standalone Rev.0 populates a USB 2.0 bridge;
- freeze ESD/TVS and connector-shield strategy;
- freeze LCD backlight current-limit components;
- build and verify the first pin-accurate tscircuit ECP5/AFE/power schematic.
