# tscircuit hardware workspace

This directory is the authoritative source for DCF77 receiver schematic and PCB design intent.

The project produces **two PCB variants from one shared receiver core**:

1. Raspberry Pi Standard HAT+ — powered from Raspberry Pi 5 V;
2. standalone board — powered from USB-C as a 5 V sink.

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
Display      NHD-C0220BIZ-FSW-FBW-3V3M, transflective 20x2 I2C LCD
PPS          mandatory dedicated ECP5 hardware output

Standalone USB-C:
connector    GCT USB4105-GF-A
CC logic     TUSB320LAIRWBR, fixed UFP/sink
power path   TPS259470ARPWR eFuse
```

Reference analog hardware is intentionally **no-trim**. Production boards must not require hand-selected antenna/filter R/C values.

The physical ECP5-45F provides development headroom, but `release_reference` RTL must satisfy the historical XC3S1400AN resource limits in `rtl/resource_budget.json`.

## Power tree

Both variants converge on the same `5V_SYS` boundary:

```text
5V_SYS
  |
  +--> low-loss passive filter -> 5V_AFE
  |      -> OPA810 / LTC1562 / LTC6912
  |
  +--> LT3042 -> 3V3_ADC_A
  |      -> LTC1407A-1 / OPA2835
  |
  +--> TPS7A20 -> 3V3_CLK
  |      -> SiT5356 TCXO
  |
  +--> TPS628502 -> 3V3_D
  |      -> ECP5 VCCIO / W25Q64 / LCD logic
  |      -> TPS7A20 -> 2V5_AUX
  |
  +--> TPS628502 -> 1V1_CORE
```

The current regulator OPNs are strong candidates; final feedback/passive values and final package suffixes are frozen with the full power-budget/PDN review.

## FPGA boot/configuration

Reference FPGA:

```text
LFE5U-45F-7BG256I
```

Reference flash:

```text
W25Q64JVSSIQ
64 Mbit
3.3 V
SOIC-8
```

Reference boot mode:

```text
Master SPI
CFG[2:0] = 010
```

JTAG is mandatory on both variants. `PROGRAMN`, `INITN` and `DONE` remain accessible for recovery/debug.

The 64 Mbit flash is deliberately large enough for a future golden/recovery image plus update image without relying on bitstream compression.

See [`../../docs/23-ecp5-boot-config.md`](../../docs/23-ecp5-boot-config.md).

## Display

Both variants use:

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2
FSTN transflective
3.3 V
I2C
```

Backlight is separately switched and normally OFF during precision RF measurements. No continuous high-frequency PWM is allowed by default.

See [`../../docs/24-lcd-display.md`](../../docs/24-lcd-display.md).

## Standalone USB-C

Reference input:

```text
USB4105-GF-A
  -> TUSB320LAIRWBR configured UFP/sink
  -> TPS259470ARPWR controlled power path
  -> 5V_SYS
```

No USB-PD is required. USB 2.0 D+/D- are retained only as an optional future debug/data path.

See [`../../docs/25-standalone-usbc-power.md`](../../docs/25-standalone-usbc-power.md).

## HAT+ variant

The HAT+ board:

- follows current HAT+ mechanical/electrical rules;
- consumes Raspberry Pi 5 V and never sources power back;
- generates receiver rails locally;
- handles Pi STANDBY without GPIO back-powering;
- uses a narrow host interface, preferably SPI + interrupt/status;
- exposes the same external hardware PPS as standalone.

Exact Raspberry Pi GPIO assignments are still open until ECP5 bank planning is frozen.

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

- ferrite / antenna tuning / OPA810 cluster;
- LTC1562 programming network;
- ADC/LT3042/OPA2835 cluster;
- TCXO/clock escape;
- ECP5/flash boot cluster;
- switcher hot loops;
- mechanically fixed LCD/connectors/holes.

No fast digital trace or switch node may run beneath or beside the ferrite/input network.

## Planned source tree

```text
hardware/tscircuit/
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

## Remaining schematic-freeze items

The major receiver architecture is now selected. Remaining electrical work is narrower:

- import/verify authoritative BG256 pin map and allocate I/O banks;
- freeze regulator feedback/passives/decoupling from final power estimate;
- choose exact HAT+ GPIO assignments;
- decide whether standalone Rev.0 actually populates a USB 2.0 bridge;
- freeze ESD/TVS parts and connector shield strategy;
- freeze LCD backlight current-limit components;
- generate the first pin-accurate tscircuit schematic.

Primary supporting documents:

- [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md)
- [`../../docs/18-adc-selection.md`](../../docs/18-adc-selection.md)
- [`../../docs/19-power-tree.md`](../../docs/19-power-tree.md)
- [`../../docs/20-antenna-input.md`](../../docs/20-antenna-input.md)
- [`../../docs/21-ltc1562-fixed-filter.md`](../../docs/21-ltc1562-fixed-filter.md)
- [`../../docs/22-ltc6912-pga.md`](../../docs/22-ltc6912-pga.md)
- [`../../docs/23-ecp5-boot-config.md`](../../docs/23-ecp5-boot-config.md)
- [`../../docs/24-lcd-display.md`](../../docs/24-lcd-display.md)
- [`../../docs/25-standalone-usbc-power.md`](../../docs/25-standalone-usbc-power.md)
