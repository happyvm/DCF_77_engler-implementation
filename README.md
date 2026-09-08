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
OPA810 FET-input buffer @ 5V_AFE
        |
        v
LTC1562 77.5 kHz analog band-pass
        |
        v
LTC6912 programmable gain
        |
        v
AC coupling / 1.25 V rebias
        |
        v
OPA2835 dual ADC driver @ clean 3.3 V
        |
        v
LTC1407AIMSE-1#PBF, 14 bit @ 930 kS/s
        |
        v
Lattice ECP5 LFE5U-45F / BG256
        |
        +--> carrier / phase
        +--> AM
        +--> PM PRN correlation
        +--> second/minute sync
        +--> 3600 s ML decoder
        +--> DCF77 clock discipline
        +--> hardware PPS
        +--> LCD
```

The integrated antenna network is intentionally **no-trim**. Fixed values are chosen so 77.5 kHz remains inside the useful antenna passband across the main L/C/input-capacitance tolerances; per-board capacitor selection is not part of the reference build. See [`docs/20-antenna-input.md`](docs/20-antenna-input.md).

The LTC1407A family is still `PRODUCTION`, so Rev.0 deliberately keeps an ADC very close to the historical receiver instead of replacing it without a measured benefit. See [`docs/18-adc-selection.md`](docs/18-adc-selection.md).

## Shared Rev.0 power tree

Both PCB variants converge on one `5V_SYS` boundary and then use the same downstream rails:

```text
5V_SYS
  |
  +--> filtered direct 5V_AFE
  |      -> OPA810 / LTC1562 / LTC6912
  |
  +--> LT3042 -> 3V3_ADC_A
  |      -> LTC1407A-1 / OPA2835
  |
  +--> TPS7A20 -> 3V3_CLK
  |      -> fixed TCXO
  |
  +--> TPS628502 -> 3V3_D
  |      -> ECP5 I/O / flash / LCD logic
  |      -> TPS7A20 -> 2V5_AUX
  |
  +--> TPS628502 -> 1V1_CORE
         -> ECP5 core
```

Switching regulators are confined to the digital/power region. The AFE is fed from a low-loss passive branch and the ADC/clock each receive their own low-noise regulator. See [`docs/19-power-tree.md`](docs/19-power-tree.md).

## Two PCB variants, one receiver core

The project produces two boards sharing the same AFE/ADC/ECP5 receiver core:

1. **Raspberry Pi Standard HAT+** — powered from Raspberry Pi 5 V;
2. **standalone USB-C** — 5 V Type-C sink with its own protected power path.

Both boards keep:

- the same integrated ferrite/AFE/ADC chain;
- the same FPGA RTL;
- the same transflective 20x2 LCD function;
- a dedicated ECP5 hardware PPS output;
- the same timing/performance validation procedure.

The standalone board is the cleaner RF/metrology reference. The HAT+ variant is compared against it under realistic Raspberry Pi activity. See [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md).

## Clock source policy

Rev.0 baseline is a **simple fixed TCXO**. DCF77 discipline is implemented digitally in the ECP5/sample-time logic. A DCTCXO remains an optional experimental population if later holdover measurements justify it.

Selection is driven by:

1. synchronized timing target;
2. holdover target;
3. exact Digi-Key/Mouser availability of an orderable OPN;
4. temperature range;
5. oscillator stability, baseline around ±100 ppb class where sourcing permits;
6. ECP5 PLL/sample-clock implementation;
7. EMI relationship to 77.5 kHz.

The portable fractional sampler remains the default safety net:

- [`rtl/core/sample_scheduler.sv`](rtl/core/sample_scheduler.sv)

See [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md).

## FPGA resource compatibility rule

The physical FPGA may be an ECP5-45F for sourcing and development headroom, but the **release receiver is not allowed to consume more resources than the historical XC3S1400AN class**.

Release limits:

```text
LUT4          <= 22,528
FF            <= 22,528
EBR18         <= 32  (576 Kibit)
MULT18X18     <= 32
```

Machine-readable policy:

- [`rtl/resource_budget.json`](rtl/resource_budget.json)

Development-only instrumentation may use spare ECP5-45F resources in a separate `lab_debug` build. Performance claimed for the receiver must be reproduced by a `release_reference` build inside the historical resource envelope. See [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md).

## Hardware CAD policy

The schematic and PCB are authored in **tscircuit**. TSX/Circuit JSON is the editable design source of truth.

Release flow:

```text
tscircuit
  -> KiCad export
  -> hard RF/mechanical constraints
  -> Quilter placement/routing
  -> native KiCad review
  -> ERC/DRC + RF/EMI inspection
  -> Gerbers/fabrication
```

Quilter is the selected placement/routing engine, but it does not get unrestricted authority over the ferrite/input network, switcher zones, clock zones or mechanically fixed parts.

Hardware workspace:

- [`hardware/tscircuit/`](hardware/tscircuit/)

See [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md).

## Display and timing outputs

Both PCB variants keep a local display in the spirit of Engeler's demonstrator.

Rev.0 preference:

```text
transflective 20x2 character LCD
backlight switchable/off during sensitive measurements
```

Both variants expose a **dedicated ECP5 hardware PPS**. The rising edge is the timing reference used for comparison against GNSS/GPS PPS during characterization.

## Documentation

- [`docs/01-dcf77-signal.md`](docs/01-dcf77-signal.md) — DCF77 AM/PM symbols and frame layout.
- [`docs/02-receiver-architecture.md`](docs/02-receiver-architecture.md) — complete receiver data path and demonstration architecture.
- [`docs/03-goertzel-detector.md`](docs/03-goertzel-detector.md) — Goertzel carrier/AM/PM detector.
- [`docs/04-time-decoder.md`](docs/04-time-decoder.md) — BCD and one-hour ML time decoder.
- [`docs/05-clock-sync-noise.md`](docs/05-clock-sync-noise.md) — Engeler clock discipline and self-interference mitigation.
- [`docs/06-hardware.md`](docs/06-hardware.md) — historical hardware and reconstruction status.
- [`docs/07-performance-targets.md`](docs/07-performance-targets.md) — sensitivity/timing targets.
- [`docs/08-reconstruction-plan.md`](docs/08-reconstruction-plan.md) — staged rebuild plan.
- [`docs/09-gaps-and-open-questions.md`](docs/09-gaps-and-open-questions.md) — unresolved and resolved items.
- [`docs/10-dcf77-pm-prn.md`](docs/10-dcf77-pm-prn.md) — PTB PRN/PZF generator.
- [`docs/11-analog-reference-design.md`](docs/11-analog-reference-design.md) — first analog proposal.
- [`docs/12-ecp5-migration.md`](docs/12-ecp5-migration.md) — ECP5 platform migration.
- [`docs/13-ecp5-clock-discipline.md`](docs/13-ecp5-clock-discipline.md) — generic clock-discipline architecture.
- [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) — tscircuit/KiCad/Quilter workflow.
- [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md) — clock-source precision/availability study.
- [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md) — XC3S1400AN-equivalent resource ceiling.
- [`docs/17-pcb-variants.md`](docs/17-pcb-variants.md) — Raspberry Pi HAT+ and standalone USB-C variants.
- [`docs/18-adc-selection.md`](docs/18-adc-selection.md) — Rev.0 LTC1407A-1 ADC and OPA2835 driver plan.
- [`docs/19-power-tree.md`](docs/19-power-tree.md) — Rev.0 low-noise power rails and ECP5 sequencing.
- [`docs/20-antenna-input.md`](docs/20-antenna-input.md) — fixed no-trim TDK ferrite and OPA810 input network.
- [`docs/references.md`](docs/references.md) — primary and manufacturer sources.

## Reconstruction policy

> Reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM.

> Do not obtain that performance merely by spending substantially more FPGA resources than Engeler had available.

> Do not replace a historical component that is still production, well stocked and technically appropriate unless the replacement provides a measured system benefit.

For the integrated Rev.0 antenna, another practical rule applies:

> Reference hardware must not require per-unit antenna tuning or hand-selected R/C values.
