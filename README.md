# DCF77 Engeler receiver recreation

Reconstruction project for the DCF77 receiver/decoder described by Daniel Engeler in **Performance Analysis and Receiver Architectures of DCF77 Radio-Controlled Clocks** (IEEE TUFFC, 2012).

The objective is to recreate the high-performance receiver architecture — ferrite antenna and analog front end, coherent digitisation, AM/PM processing, second/minute synchronisation, carrier discipline and one-hour ML time decoding — while replacing obsolete 2012 parts with maintainable modern equivalents.

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
~14-16 bit SAR ADC @ 930 kS/s
        |
        v
Lattice ECP5 LFE5U-45F / BG256
        |
        +--> carrier / phase
        +--> AM
        +--> PM PRN correlation
        +--> second/minute sync
        +--> 3600 s ML decoder
        +--> clock discipline

SiTime SiT5348 DCTCXO @ 24.180000 MHz
        |
        +--> ECP5 PLL -> 120.900 MHz
        |                  |
        |                  +--> exact /130 = 930 kS/s
        |
        +<-- I2C discipline from DCF77 carrier phase
```

## Hardware CAD policy

The schematic and PCB will be authored in **tscircuit**. The TSX/Circuit JSON design is the editable source of truth; KiCad is an export/review/manufacturing validation target.

AI/cloud placement and routing may be used, but RF-critical placement constraints remain explicit and every release must be independently checked in KiCad before fabrication.

Hardware workspace: [`hardware/tscircuit/`](hardware/tscircuit/)

## Documentation

- [`docs/01-dcf77-signal.md`](docs/01-dcf77-signal.md) — DCF77 AM/PM symbols and frame layout.
- [`docs/02-receiver-architecture.md`](docs/02-receiver-architecture.md) — complete receiver data path and demonstration architecture.
- [`docs/03-goertzel-detector.md`](docs/03-goertzel-detector.md) — Goertzel carrier/AM/PM detector, synchronisation and fixed-point implementation notes.
- [`docs/04-time-decoder.md`](docs/04-time-decoder.md) — conventional BCD decoder and the ML decoder.
- [`docs/05-clock-sync-noise.md`](docs/05-clock-sync-noise.md) — Engeler clock discipline, burst-noise rejection and self-interference mitigation.
- [`docs/06-hardware.md`](docs/06-hardware.md) — recovered hardware, part clarification and reconstruction status.
- [`docs/07-performance-targets.md`](docs/07-performance-targets.md) — sensitivity, timing and performance targets.
- [`docs/08-reconstruction-plan.md`](docs/08-reconstruction-plan.md) — staged rebuild/validation plan.
- [`docs/09-gaps-and-open-questions.md`](docs/09-gaps-and-open-questions.md) — remaining unknowns and resolved gaps.
- [`docs/10-dcf77-pm-prn.md`](docs/10-dcf77-pm-prn.md) — PTB PRN/PZF generator and PM timing.
- [`docs/11-analog-reference-design.md`](docs/11-analog-reference-design.md) — first buildable analog proposal.
- [`docs/12-ecp5-migration.md`](docs/12-ecp5-migration.md) — ECP5 target, configuration, power and RTL portability.
- [`docs/13-ecp5-clock-discipline.md`](docs/13-ecp5-clock-discipline.md) — current clock-discipline architecture and generic-XO fallback.
- [`docs/14-hardware-cad-tscircuit.md`](docs/14-hardware-cad-tscircuit.md) — tscircuit source-of-truth, AI routing and KiCad export/review flow.
- [`docs/15-sitime-super-tcxo.md`](docs/15-sitime-super-tcxo.md) — SiT5348 DCTCXO selection and exact 24.18 MHz clock plan.
- [`docs/references.md`](docs/references.md) — Engeler, PTB and manufacturer sources.

## Useful implementation files

- [`tools/dcf77_prn.py`](tools/dcf77_prn.py) — 512-chip DCF77 PM sequence generator.
- [`tools/clock_plan.py`](tools/clock_plan.py) — calculations for the earlier generic-XO fractional scheduler.
- [`rtl/core/sample_scheduler.sv`](rtl/core/sample_scheduler.sv) — vendor-neutral fractional scheduler retained as fallback/reference.

## FPGA target

The historical Xilinx XC3S1400AN is not used in the new board.

Current target:

```text
Lattice ECP5
LFE5U-45F
BG256 / caBGA256
```

A future cost reduction may evaluate the 25F if the completed design fits comfortably.

## Clock target

The preferred oscillator is no longer a generic 25 MHz XO.

The board now targets a programmable **SiTime SiT5348 Super-TCXO / DCTCXO at 24.180000 MHz**.

The frequency was chosen because:

```text
24.18 MHz  = 312 * 77.5 kHz
24.18 MHz  = 26  * 930 kHz
120.90 MHz = 5 * 24.18 MHz
120.90 MHz = 130 * 930 kHz
```

Therefore the ECP5 can generate exactly one ADC sample event every 130 system clocks. DCF77 carrier phase can discipline the SiT5348 itself over I2C, keeping the FPGA/ADC clock relationships coherent without fractional sample-time dithering.

The previous 25 MHz -> 125 MHz + 40-bit fractional scheduler remains a supported fallback architecture.

## Key target values

| Item | Target / implementation value |
|---|---:|
| DCF77 carrier | 77.5 kHz |
| ADC rate | 930 kS/s = 12 × carrier |
| historical FPGA | Xilinx XC3S1400AN |
| rebuild FPGA | Lattice ECP5 LFE5U-45F / BG256 |
| preferred clock source | SiTime SiT5348 DCTCXO |
| preferred clock frequency | 24.180000 MHz |
| ECP5 system clock | 120.900 MHz |
| system clocks / ADC sample | 130 exactly |
| TCXO stability target | ±0.05 ppm class |
| DCF77 disciplined clock target | ~0.1 ppm or better |
| ML history | 3600 s |
| Goertzel AM 3 dB bandwidth | ~15 Hz |
| Goertzel PM 3 dB bandwidth | ~930 Hz |
| PM correlation processing | carrier / 20 = 3.875 kHz |
| PRN chip rate | carrier / 120 = 645.833... Hz |
| PRN length | 512 chips |
| PRN active window | 200 ms to ~992.774 ms |
| PM phase excursion | approximately ±13° |
| Engeler measured first-sync spread | 362 µs over 54 tests |

## Reconstruction policy

The paper is not a complete construction dossier. The repository labels information as:

- directly documented by Engeler;
- recovered from PTB primary sources;
- manufacturer data-sheet facts;
- external evidence requiring validation;
- explicit new reconstruction choices.

A central project rule is:

> Reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM.

A second rule now applies to PCB design:

> Keep the electrical and physical design regenerable from tscircuit source; never make an opaque AI/KiCad edit the only copy of a critical design decision.

## Current status

Resolved/selected:

- paper converted to structured implementation documentation;
- source PDF archived;
- DCF77 PRN generator recovered and implemented;
- ECP5 selected, current target LFE5U-45F/BG256;
- tscircuit selected for schematic/PCB source;
- KiCad selected as mandatory export/review path;
- SiTime SiT5348 DCTCXO selected as preferred reference-clock family;
- 24.180000 MHz selected to produce exact integer DCF77/ADC clock ratios;
- first LTC1562 reconstruction values documented.

Still to freeze:

- ferrite antenna electrical characterization;
- replacement for BF245A/input topology;
- sustainable analog band-pass implementation versus reference LTC1562;
- PGA choice;
- final SAR ADC and driver;
- exact SiT5348 ordering code;
- ECP5 exact speed/temp OPN;
- SPI configuration flash;
- regulator/power tree;
- carrier-discipline loop coefficients;
- complete tscircuit schematic and placement constraints.

## Recommended next implementation order

1. choose the final ADC and its input driver;
2. choose the replacement antenna input stage;
3. freeze ECP5 + SiT5348 + SPI flash + power tree;
4. create the first complete tscircuit schematic/netlist;
5. validate power/clock/ADC capture on the ECP5;
6. place the board with strict RF/EMI zones before autorouting;
7. export to KiCad and run independent ERC/DRC/review;
8. fabricate Rev.0;
9. capture raw DCF77 data and implement carrier/AM/PM processing;
10. close DCTCXO carrier discipline, then add ML decoding.
