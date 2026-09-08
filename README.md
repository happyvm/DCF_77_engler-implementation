# DCF77 Engeler receiver recreation

Reconstruction of the high-performance DCF77 receiver/decoder described by Daniel Engeler, with maintainable hardware while preserving the original signal-processing architecture and FPGA resource class.

The original paper is archived under [`archive/papers/Engeler_DCF77.pdf`](archive/papers/Engeler_DCF77.pdf).

## Rev.0 board

Rev.0 now has **one PCB only**:

> Raspberry Pi Standard HAT+

The previously planned standalone USB-C board has been removed. There is no Type-C power path, standalone eFuse, standalone 3.3 V buck or standalone-specific host/debug path in the reference design.

## Current Rev.0 signal chain

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
        +--> dedicated hardware PPS
        +--> Raspberry Pi SPI host
        +--> local LCD
```

The antenna, LTC1562 filter and power network are intentionally **no-trim/no-selection**. Reference boards do not require hand-selected R/C values.

## HAT+ power architecture

The HAT deliberately consumes both Raspberry Pi header rails:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure / 0R link -> 3V3_D
```

`PI_3V3` powers only the digital I/O/configuration domain. ADC, TCXO, AFE, ECP5 core and LCD backlight remain locally powered from the Pi 5 V path.

Reference tree:

```text
PI_5V
  -> TPS22975NDSGR
  -> 5V_SYS
       +--> 0.10 ohm fixed branch -> 5V_AFE
       |      -> OPA810 / LTC1562 / LTC6912
       |
       +--> LT3042EMSE#PBF -> 3V3_ADC_A
       |      -> LTC1407A-1 / OPA2835
       |
       +--> TPS7A2033PDQNR -> 3V3_CLK
       |      -> SiT5356
       |
       +--> TPS628502DRLR -> 1V1_CORE
              -> ECP5 VCC

PI_3V3
  -> current-measure / 0R
  -> 3V3_D
       +--> ECP5 VCCIO / VCCIO8
       +--> W25Q64JV
       +--> HAT ID EEPROM
       +--> LCD logic
       +--> PPS / Pi host I/O
       +--> TPS7A2025PDQNR -> 2V5_AUX
```

The sole local buck is the 1.1 V ECP5 core converter. It runs forced PWM with SSC disabled and a nominal switching frequency around 3.125 MHz. The internal 2.25 MHz nominal setting is deliberately avoided because:

```text
29 * 77.5 kHz = 2.2475 MHz
```

Exact power values and sequencing are frozen in:

- [`docs/19-power-tree.md`](docs/19-power-tree.md)
- [`docs/26-hat-power.md`](docs/26-hat-power.md)
- [`docs/28-power-passives-sequencing.md`](docs/28-power-passives-sequencing.md)
- [`hardware/tscircuit/power-plan.json`](hardware/tscircuit/power-plan.json)

## Clock source

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

## FPGA, flash and HAT pin plan

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

The flash supports a future golden/recovery image plus update image. JTAG remains mandatory on the HAT.

Pin planning is frozen in:

- [`docs/23-ecp5-boot-config.md`](docs/23-ecp5-boot-config.md)
- [`docs/27-ecp5-pin-plan-hat.md`](docs/27-ecp5-pin-plan-hat.md)
- [`hardware/tscircuit/pin-plan.json`](hardware/tscircuit/pin-plan.json)

HAT runtime interface:

```text
SPI0 MOSI/MISO/SCLK/CE0
IRQ / DATA_READY
RESET/control
PPS copy to GPIO4
```

The dedicated external PPS path is separate from the Pi GPIO copy and remains the timing/metrology reference.

## Display

```text
NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 FSTN transflective LCD
3.3 V I2C
```

LCD logic uses Pi-derived `3V3_D`. Backlight is powered from `5V_SYS`, switched separately and normally OFF in precision RF mode.

See [`docs/24-lcd-display.md`](docs/24-lcd-display.md).

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

## Hardware CAD policy

The schematic and PCB are authored in **tscircuit**. TSX/Circuit JSON is the editable design source of truth.

Machine-readable design inputs:

```text
hardware/tscircuit/pin-plan.json
hardware/tscircuit/power-plan.json
```

Release flow:

```text
tscircuit HAT design
  -> Circuit JSON / KiCad
  -> HAT+ RF/mechanical constraints
  -> Quilter placement/routing
  -> native KiCad review
  -> ERC/DRC + RF/EMI inspection
  -> Gerbers/fabrication
```

Quilter does not have unrestricted authority over the ferrite/input network, filter/PGA, ADC island, TCXO, FPGA/flash boot cluster, 1.1 V buck, PPS path or mechanically fixed HAT/LCD components.

See [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) and [`hardware/tscircuit/`](hardware/tscircuit/).

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
- [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) — HAT-only tscircuit/KiCad/Quilter workflow.
- [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md) — fixed SiT5356 clock selection.
- [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md) — historical FPGA ceiling.
- [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md) — single Raspberry Pi HAT+ board architecture.
- [`docs/18-adc-selection.md`](docs/18-adc-selection.md) — LTC1407A-1 ADC and driver.
- [`docs/19-power-tree.md`](docs/19-power-tree.md) — HAT power architecture.
- [`docs/20-antenna-input.md`](docs/20-antenna-input.md) — fixed TDK ferrite/input network.
- [`docs/21-ltc1562-fixed-filter.md`](docs/21-ltc1562-fixed-filter.md) — fixed LTC1562 BPF.
- [`docs/22-ltc6912-pga.md`](docs/22-ltc6912-pga.md) — LTC6912-1 PGA and AGC policy.
- [`docs/23-ecp5-boot-config.md`](docs/23-ecp5-boot-config.md) — ECP5/flash/JTAG boot.
- [`docs/24-lcd-display.md`](docs/24-lcd-display.md) — HAT LCD selection.
- [`docs/26-hat-power.md`](docs/26-hat-power.md) — Pi 5 V + 3.3 V power split.
- [`docs/27-ecp5-pin-plan-hat.md`](docs/27-ecp5-pin-plan-hat.md) — BG256/HAT pin plan.
- [`docs/28-power-passives-sequencing.md`](docs/28-power-passives-sequencing.md) — exact HAT power passives/sequencing.
- [`docs/references.md`](docs/references.md) — primary/manufacturer references.

## Reconstruction policy

> Reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM.

> Do not obtain that performance merely by spending substantially more FPGA resources than Engeler had available.

> Do not replace a historical component that is still production, well stocked and technically appropriate unless the replacement provides a measured system benefit.

> Reference hardware must not require per-unit antenna/filter/power tuning or hand-selected R/C values.
