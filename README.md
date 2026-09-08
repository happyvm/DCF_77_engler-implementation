# DCF77 Engeler receiver recreation

Reconstruction of the high-performance DCF77 receiver/decoder described by Daniel Engeler, with modern maintainable components while preserving the original signal-processing architecture and FPGA resource class.

The original paper is archived under [`archive/papers/Engeler_DCF77.pdf`](archive/papers/Engeler_DCF77.pdf).

## Current rebuild direction

```text
77.5 kHz ferrite antenna
        |
        v
high-impedance low-noise input stage
        |
        v
77.5 kHz analog band-pass
        |
        v
programmable gain
        |
        v
~14-16 bit SAR ADC @ nominal 930 kS/s
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
```

The physical FPGA may be an ECP5-45F, but the **release receiver is not allowed to consume more resources than the historical XC3S1400AN class**. See [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md).

## Clock source: not frozen yet

The previous SiT5348/24.18 MHz proposal is now only an engineering study, not a BOM decision.

Clock selection is driven by:

1. final synchronized timing target;
2. holdover requirement;
3. exact distributor availability of an orderable OPN;
4. temperature range;
5. DCTCXO pull/control capability;
6. ECP5 PLL/sample-clock implementation;
7. EMI relationship to the 77.5 kHz carrier.

The current baseline is a **stocked SiTime DCTCXO around the ±100 ppb class**, with standard frequencies such as 10, 25 or 26 MHz under evaluation. A custom frequency will only be used if measurements show a system-level benefit worth the sourcing risk.

The portable fractional sampler remains the default safety net:

```text
rtl/core/sample_scheduler.sv
```

so the ADC can still average exactly 930 kS/s without requiring an exotic oscillator frequency.

See [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md).

## FPGA resource compatibility rule

Historical XC3S1400AN envelope:

```text
11,264 slices
22,528 LUT4-equivalent functions
22,528 CLB flip-flops
176 Kibit distributed RAM
576 Kibit block RAM
32 dedicated 18x18 multipliers
8 DCMs
```

Release limits on ECP5:

```text
LUT4          <= 22,528
FF            <= 22,528
EBR18         <= 32  (576 Kibit)
MULT18X18     <= 32
```

Machine-readable policy:

- [`rtl/resource_budget.json`](rtl/resource_budget.json)

Development-only instrumentation may use spare 45F resources in a separate `lab_debug` build, but the performance claimed for the receiver must be reproduced by a `release_reference` build inside the historical resource envelope.

## Hardware CAD policy

The schematic and PCB will be authored in **tscircuit**. TSX/Circuit JSON is the editable source of truth; KiCad is the export, review and manufacturing-validation target.

AI/cloud placement and routing may be used only after explicit RF/EMI placement constraints are applied. Every release must pass KiCad inspection/DRC before fabrication.

Hardware workspace:

- [`hardware/tscircuit/`](hardware/tscircuit/)

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
- [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) — tscircuit/KiCad/AI CAD workflow.
- [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md) — clock-source selection by precision and availability.
- [`docs/16-fpga-resource-budget.md`](docs/16-fpga-resource-budget.md) — XC3S1400AN-equivalent resource ceiling.
- [`docs/references.md`](docs/references.md) — primary and manufacturer sources.

## Useful implementation files

- [`tools/dcf77_prn.py`](tools/dcf77_prn.py) — verified 512-chip PM sequence generator.
- [`tools/clock_plan.py`](tools/clock_plan.py) — fractional sample-clock calculations.
- [`rtl/core/sample_scheduler.sv`](rtl/core/sample_scheduler.sv) — vendor-neutral fractional ADC scheduler.
- [`rtl/resource_budget.json`](rtl/resource_budget.json) — release resource limits.

## Reconstruction policy

Two rules govern the project:

> Reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM.

> Do not obtain that performance merely by spending substantially more FPGA resources than Engeler had available.

The result should therefore be a maintainable modern receiver whose architecture and computational scale remain meaningfully comparable to the original work.
