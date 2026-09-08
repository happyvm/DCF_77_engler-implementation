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

## Variant power architecture

The precision/analog rails remain locally generated on both boards, but the source of the digital 3.3 V rail now differs intentionally.

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

The HAT consumes both header rails:

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
       +--> ECP5 VCCIO / VCCIO8
       +--> W25Q64JV
       +--> HAT ID EEPROM
       +--> LCD logic
       +--> PPS / Pi host-I/O domain
       +--> TPS7A20 -> 2V5_AUX under controlled enable
```

The HAT therefore does **not** populate the standalone board's 3.3 V buck. This removes one local switching converter from the HAT PCB and directly matches Raspberry Pi GPIO voltage.

`PI_3V3` is digital-only. It never powers:

```text
ADC / OPA2835
SiT5356 TCXO
OPA810 / LTC1562 / LTC6912
ECP5 1.1 V core
LCD backlight
```

See [`../../docs/26-hat-power.md`](../../docs/26-hat-power.md).

## HAT+ STANDBY policy

HAT+ STANDBY keeps Pi 5 V present while Pi 3.3 V is removed.

Use `PI_3V3` presence as the HAT-active indication:

```text
PI_3V3 present -> 3V3_D valid -> enable 5V_SYS/local rails
PI_3V3 absent  -> 3V3_D off   -> disable 5V_SYS/local rails
```

No alternate source may back-power `3V3_D` when the Raspberry Pi 3.3 V rail is absent.

The HAT must include a current-measure link on `PI_3V3`. Final current budget is validated against the supported Raspberry Pi models; the analog, TCXO, FPGA core and backlight loads are deliberately excluded from this rail.

## FPGA boot/configuration

```text
LFE5U-45F-7BG256I
W25Q64JVSSIQ, 64 Mbit
Master SPI
CFG[2:0] = 010
```

JTAG is mandatory on both variants. `PROGRAMN`, `INITN` and `DONE` remain accessible.

The 64 Mbit flash supports a future golden/recovery image plus update image without requiring bitstream compression.

See [`../../docs/23-ecp5-boot-config.md`](../../docs/23-ecp5-boot-config.md).

## Display

Both variants use:

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2
FSTN transflective
3.3 V I2C
```

LCD logic uses `3V3_D`. Backlight is separately switched and normally OFF during precision RF measurements. On the HAT, backlight current comes from `5V_SYS`, not `PI_3V3`.

See [`../../docs/24-lcd-display.md`](../../docs/24-lcd-display.md).

## Standalone USB-C

```text
USB4105-GF-A
  -> TUSB320LAIRWBR UFP/sink
  -> TPS259470ARPWR controlled power path
  -> 5V_SYS
```

No USB-PD is required. USB 2.0 D+/D- remain optional for a future debug/data path.

See [`../../docs/25-standalone-usbc-power.md`](../../docs/25-standalone-usbc-power.md).

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
- TCXO/clock escape;
- ECP5/flash boot cluster;
- power-converter hot loops;
- mechanically fixed LCD/connectors/holes.

No fast digital trace or switch node may run beneath or beside the ferrite/input network.

## Planned source tree

```text
hardware/tscircuit/
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

- import/verify authoritative BG256 pin map and allocate I/O banks;
- freeze regulator feedback/passives/decoupling from final power estimate;
- choose exact HAT+ GPIO assignments;
- freeze HAT `PI_3V3` current/protection/decoupling implementation;
- decide whether standalone Rev.0 populates a USB 2.0 bridge;
- freeze ESD/TVS and connector-shield strategy;
- freeze LCD backlight current-limit components;
- generate the first pin-accurate tscircuit schematic.

Primary supporting documents include `docs/15` through `docs/26`, with `docs/26-hat-power.md` defining the HAT-specific dual-rail power split.
