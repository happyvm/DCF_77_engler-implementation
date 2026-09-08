# DCF77 Engeler receiver recreation

Reconstruction of the high-performance DCF77 receiver/decoder described by Daniel Engeler, with maintainable hardware while preserving the original signal-processing architecture and FPGA resource class.

The original paper is archived under [`archive/papers/Engeler_DCF77.pdf`](archive/papers/Engeler_DCF77.pdf).

## Current Rev.0 direction

```text
TDK B82453C0275A000 ferrite, X winding
        || 560 pF C0G
        || 22 pF C0G
        || 330 kOhm damping
        |
        v
OPA810IDBVR FET-input buffer @ 5V_AFE
        |
        v
LTC1562IG#PBF fixed 77.5 kHz / ~7.75 kHz BPF
        |
        v
LTC6912IGN-1#PBF programmable gain
        |  1 / 2 / 5 / 10 / 20 / 50 / 100
        v
AC coupling / 1.25 V rebias
        |
        v
OPA2835IDGSR dual ADC driver @ 3V3_ADC_A
        |
        v
LTC1407AIMSE-1#PBF, 14 bit @ 930 kS/s
        |
        v
Lattice LFE5U-45F-7BG256I
        ^
        |
SiT5356AI-FQ-33E0-25.000000 fixed TCXO
25 MHz / 3.3 V / ±100 ppb
        |
        +--> carrier / phase
        +--> AM
        +--> PM PRN correlation
        +--> second/minute sync
        +--> 3600 s ML decoder
        +--> DCF77 digital clock discipline
        +--> hardware PPS
        +--> LCD
```

The antenna, LTC1562 filter and power network are intentionally **no-trim/no-selection**. Reference boards do not require hand-selected R/C values.

## Two PCB variants, one receiver core

The project produces:

1. **Raspberry Pi Standard HAT+**;
2. **standalone USB-C receiver**.

Both keep the same AFE/ADC/ECP5/clock/PPS/LCD architecture and the same FPGA RTL.

### HAT+ power

The HAT intentionally consumes both Raspberry Pi header rails:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure link -> 3V3_D
```

`PI_3V3` powers the digital I/O/configuration domain only. ADC, TCXO, AFE, ECP5 core and LCD backlight remain locally powered from the Pi 5 V path.

This removes the local 3.3 V switching converter from the HAT and naturally follows HAT+ STANDBY behavior.

See [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md) and [`docs/26-hat-power.md`](docs/26-hat-power.md).

### Standalone USB-C

```text
USB4105-GF-A
  -> TUSB320LAIRWBR UFP/sink
  -> TPS259470ARPWR eFuse
  -> 5V_SYS
```

No USB-PD is required for Rev.0. USB 2.0 data remains optional.

See [`docs/25-standalone-usbc-power.md`](docs/25-standalone-usbc-power.md).

## Frozen Rev.0 power tree

Common precision/analog rails:

```text
5V_SYS
  +--> 0.10 ohm fixed RC branch -> 5V_AFE
  +--> LT3042EMSE#PBF -> 3V3_ADC_A
  +--> TPS7A2033PDQNR -> 3V3_CLK
  +--> TPS628502DRLR -> 1V1_CORE

3V3_D
  +--> TPS7A2025PDQNR -> 2V5_AUX
```

Digital 3.3 V source:

```text
standalone: 5V_SYS -> TPS628502DRLR -> 3V3_D
HAT+:       PI_3V3 -----------------> 3V3_D
```

The TPS628502 reference implementation uses forced PWM, SSC off and a nominal switching frequency around 3.125 MHz. The internal 2.25 MHz default is deliberately avoided because `29 × 77.5 kHz = 2.2475 MHz`.

Exact passives, sequencing and ECP5 decoupling are frozen in:

- [`docs/19-power-tree.md`](docs/19-power-tree.md)
- [`docs/28-power-passives-sequencing.md`](docs/28-power-passives-sequencing.md)
- [`hardware/tscircuit/power-plan.json`](hardware/tscircuit/power-plan.json)

## Clock source

Reference TCXO:

```text
SiTime SiT5356AI-FQ-33E0-25.000000
25 MHz
fixed TCXO
3.3 V LVCMOS
±100 ppb
-40...+85 degC
```

The 25 MHz clock feeds the ECP5 PLL; the reference system clock is 125 MHz. A 40-bit fractional scheduler produces the 930 kS/s average ADC cadence and applies DCF77 frequency correction digitally.

DCTCXO remains experimental only.

See [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md).

## FPGA, flash and pin plan

Reference FPGA:

```text
LFE5U-45F-7BG256I
plain ECP5 / no SERDES
BG256 14 x 14 mm / 0.8 mm
industrial speed grade -7
```

Reference flash:

```text
W25Q64JVSSIQ
64 Mbit
Master SPI
```

64 Mbit permits a future golden/recovery image plus update image without depending on bitstream compression. JTAG is mandatory on both variants.

The ECP5 bank/ball plan and HAT GPIO assignments are frozen in:

- [`docs/23-ecp5-boot-config.md`](docs/23-ecp5-boot-config.md)
- [`docs/27-ecp5-pin-plan-hat.md`](docs/27-ecp5-pin-plan-hat.md)
- [`hardware/tscircuit/pin-plan.json`](hardware/tscircuit/pin-plan.json)

## FPGA resource compatibility rule

The physical ECP5-45F provides sourcing/development headroom, but the **release receiver may not consume more resources than the historical XC3S1400AN class**.

```text
LUT4          <= 22,528
FF            <= 22,528
EBR18         <= 32  (576 Kibit)
MULT18X18     <= 32
```

Machine-readable policy:

- [`rtl/resource_budget.json`](rtl/resource_budget.json)

Development-only instrumentation may use spare ECP5-45F resources in a separate `lab_debug` profile. Performance claims must also be reproduced by `release_reference` inside the historical envelope.

See [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md).

## Display and timing outputs

Both boards use:

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 FSTN transflective LCD
3.3 V I2C
```

The backlight is separately switched and normally OFF in precision RF mode.

Both boards expose a **dedicated ECP5 hardware PPS**. The rising edge is the metrology reference for GNSS/GPS comparison; the HAT also routes a secondary PPS copy to a Raspberry Pi GPIO.

See [`docs/24-lcd-display.md`](docs/24-lcd-display.md) and [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md).

## Hardware CAD policy

The schematic and PCB are authored in **tscircuit**. TSX/Circuit JSON is the editable design source of truth.

Current machine-readable design inputs:

```text
hardware/tscircuit/pin-plan.json
hardware/tscircuit/power-plan.json
```

Release flow:

```text
tscircuit
  -> Circuit JSON / KiCad
  -> hard RF/mechanical constraints
  -> Quilter placement/routing
  -> native KiCad review
  -> ERC/DRC + RF/EMI inspection
  -> Gerbers/fabrication
```

Quilter does not have unrestricted authority over the ferrite/input network, filter/PGA, ADC island, TCXO, FPGA/flash boot cluster, power hot loops or mechanically fixed components.

Hardware workspace:

- [`hardware/tscircuit/`](hardware/tscircuit/)

## Documentation

- [`docs/01-dcf77-signal.md`](docs/01-dcf77-signal.md) — DCF77 AM/PM signal and frame.
- [`docs/02-receiver-architecture.md`](docs/02-receiver-architecture.md) — receiver data path.
- [`docs/03-goertzel-detector.md`](docs/03-goertzel-detector.md) — Goertzel detector.
- [`docs/04-time-decoder.md`](docs/04-time-decoder.md) — BCD / one-hour ML decoder.
- [`docs/05-clock-sync-noise.md`](docs/05-clock-sync-noise.md) — clock discipline/self-interference.
- [`docs/06-hardware.md`](docs/06-hardware.md) — historical hardware/reconstruction status.
- [`docs/07-performance-targets.md`](docs/07-performance-targets.md) — sensitivity/timing targets.
- [`docs/08-reconstruction-plan.md`](docs/08-reconstruction-plan.md) — staged rebuild plan.
- [`docs/09-gaps-and-open-questions.md`](docs/09-gaps-and-open-questions.md) — unresolved/resolved items.
- [`docs/10-dcf77-pm-prn.md`](docs/10-dcf77-pm-prn.md) — exact PTB PM/PZF sequence.
- [`docs/11-analog-reference-design.md`](docs/11-analog-reference-design.md) — analog reconstruction basis.
- [`docs/12-ecp5-migration.md`](docs/12-ecp5-migration.md) — ECP5 migration.
- [`docs/13-ecp5-clock-discipline.md`](docs/13-ecp5-clock-discipline.md) — fractional timing architecture.
- [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) — tscircuit/KiCad/Quilter workflow.
- [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md) — fixed SiT5356 clock selection.
- [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md) — historical FPGA ceiling.
- [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md) — HAT+ / standalone variants and PPS.
- [`docs/18-adc-selection.md`](docs/18-adc-selection.md) — LTC1407A-1 ADC and driver.
- [`docs/19-power-tree.md`](docs/19-power-tree.md) — current power architecture.
- [`docs/20-antenna-input.md`](docs/20-antenna-input.md) — fixed TDK ferrite/input network.
- [`docs/21-ltc1562-fixed-filter.md`](docs/21-ltc1562-fixed-filter.md) — fixed LTC1562 BPF.
- [`docs/22-ltc6912-pga.md`](docs/22-ltc6912-pga.md) — LTC6912-1 PGA and AGC policy.
- [`docs/23-ecp5-boot-config.md`](docs/23-ecp5-boot-config.md) — ECP5/flash/JTAG boot.
- [`docs/24-lcd-display.md`](docs/24-lcd-display.md) — LCD selection.
- [`docs/25-standalone-usbc-power.md`](docs/25-standalone-usbc-power.md) — standalone Type-C input.
- [`docs/26-hat-power.md`](docs/26-hat-power.md) — Pi 5 V + 3.3 V HAT power split.
- [`docs/27-ecp5-pin-plan-hat.md`](docs/27-ecp5-pin-plan-hat.md) — BG256/HAT pin plan.
- [`docs/28-power-passives-sequencing.md`](docs/28-power-passives-sequencing.md) — exact power passives and sequencing.
- [`docs/references.md`](docs/references.md) — primary/manufacturer references.

## Reconstruction policy

> Reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM.

> Do not obtain that performance merely by spending substantially more FPGA resources than Engeler had available.

> Do not replace a historical component that is still production, well stocked and technically appropriate unless the replacement provides a measured system benefit.

> Reference hardware must not require per-unit antenna/filter/power tuning or hand-selected R/C values.
