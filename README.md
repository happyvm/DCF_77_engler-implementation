# DCF77 Engeler receiver recreation

Reconstruction project for the DCF77 receiver/decoder described by Daniel Engeler in **Performance Analysis and Receiver Architectures of DCF77 Radio-Controlled Clocks** (IEEE TUFFC, 2012).

The objective of this repository is not merely to decode the conventional DCF77 amplitude pulse. It is to recreate, as closely as practical, the high-performance demonstration receiver from the paper: ferrite antenna and analog front-end, digitisation at 12 × 77.5 kHz, carrier/AM/PM processing, second/minute synchronisation, and the one-hour maximum-likelihood (ML) time decoder.

The original paper is kept only as a source document under [`archive/papers/Engeler_DCF77.pdf`](archive/papers/Engeler_DCF77.pdf). The Markdown documentation is an implementation-oriented engineering reconstruction of the paper plus authoritative PTB/manufacturer material needed to fill gaps that the article does not contain.

## Documentation

- [`docs/01-dcf77-signal.md`](docs/01-dcf77-signal.md) — DCF77 AM/PM symbols and frame layout.
- [`docs/02-receiver-architecture.md`](docs/02-receiver-architecture.md) — complete receiver data path and demonstration architecture.
- [`docs/03-goertzel-detector.md`](docs/03-goertzel-detector.md) — Goertzel carrier/AM/PM detector, synchronisation and fixed-point implementation notes.
- [`docs/04-time-decoder.md`](docs/04-time-decoder.md) — conventional BCD decoder and the ML decoder used by the demonstration receiver.
- [`docs/05-clock-sync-noise.md`](docs/05-clock-sync-noise.md) — Engeler clock discipline, burst-noise rejection and clock-leakage mitigation.
- [`docs/06-hardware.md`](docs/06-hardware.md) — recovered hardware, part-number clarification and reconstruction status.
- [`docs/07-performance-targets.md`](docs/07-performance-targets.md) — performance figures, sensitivity, timing and range targets.
- [`docs/08-reconstruction-plan.md`](docs/08-reconstruction-plan.md) — staged plan to rebuild and validate the receiver.
- [`docs/09-gaps-and-open-questions.md`](docs/09-gaps-and-open-questions.md) — remaining unknowns, with resolved items separated from genuine gaps.
- [`docs/10-dcf77-pm-prn.md`](docs/10-dcf77-pm-prn.md) — exact PTB PRN/PZF generator, timing and PM minute marker.
- [`docs/11-analog-reference-design.md`](docs/11-analog-reference-design.md) — first buildable analog front-end proposal and BOM.
- [`docs/12-ecp5-migration.md`](docs/12-ecp5-migration.md) — ECP5 target, resources, configuration, power and HDL-portability plan.
- [`docs/13-ecp5-clock-discipline.md`](docs/13-ecp5-clock-discipline.md) — fixed ECP5 PLL, fractional 930 kS/s scheduler and carrier-discipline architecture.
- [`docs/references.md`](docs/references.md) — Engeler, PTB and manufacturer sources.

Useful implementation files:

- [`tools/dcf77_prn.py`](tools/dcf77_prn.py) — executable 512-chip DCF77 PM sequence generator with verification invariants.
- [`tools/clock_plan.py`](tools/clock_plan.py) — reproduces sample-accumulator, ppm-resolution and jitter-budget calculations.
- [`rtl/core/sample_scheduler.sv`](rtl/core/sample_scheduler.sv) — portable fractional ADC conversion scheduler; no FPGA-vendor primitives.

## Demonstration receiver in one diagram

```mermaid
flowchart LR
    A[HKW FTD02011R\nferrite antenna] --> B[BF245A\nJFET input amplifier]
    B --> C[LTC1562\n8th-order band-pass]
    C --> D[LTC6912\nprogrammable gain]
    D --> E[LTC1407 family\n14-bit A variant\n930 kS/s]
    E --> F[Xilinx XC3S1400AN\nhistorical FPGA]
    F --> G[carrier / phase detect]
    G --> H[Goertzel PM correlation]
    H --> I[second sync + detection]
    I --> J[ML time decoder\n3600 s history]
    J --> K[LCD / local clock]
    F --> D
    F --> L[clock discipline]
    L --> F
    F --> M[USB / debug / DAC]
```

## Rebuild FPGA target

The historical XC3S1400AN will **not** be used for the new implementation. The current first-choice target is:

```text
Lattice ECP5 LFE5U-45F
caBGA256 / BG256
no SERDES required
```

The 45F gives comfortable margin for the Goertzel paths, PRN correlator, debug instrumentation and ML decoder. The board and HDL should preserve a possible LFE5U-25F population where pin/resource usage permits. See [`docs/12-ecp5-migration.md`](docs/12-ecp5-migration.md).

## Rebuild clock architecture

The ECP5 PLL stays fixed. DCF77 disciplines the **ADC conversion scheduler**, not the FPGA PLL:

```text
25.000 MHz standard LVCMOS XO
          |
          v
ECP5 PLL -> 125.000 MHz fixed FPGA clock
                         |
                         v
                  40-bit phase accumulator
                         |
                         +--> ADC CONV/sample_ce
                              average 930 kS/s
                              trim controlled by carrier phase
```

Current numerical design point:

```text
phase width        40 bits
nominal increment  8,180,366,511
numerical error    about +0.000042 ppm
trim resolution    about 0.000122 ppm / increment LSB
system-clock grid  8 ns
```

This preserves Engeler's occasional-clock-correction principle without runtime PLL reconfiguration. Full reasoning and verification requirements are in [`docs/13-ecp5-clock-discipline.md`](docs/13-ecp5-clock-discipline.md).

## Key target values

| Item | Target / implementation value |
|---|---:|
| DCF77 carrier | 77.5 kHz |
| ADC rate | 930 kS/s = 12 × carrier |
| ADC | LTC1407 family, 14-bit A variant in the historical receiver |
| historical FPGA | Xilinx XC3S1400AN |
| rebuild FPGA | Lattice ECP5 LFE5U-45F, BG256 preferred |
| rebuild FPGA reference XO | standard 25 MHz LVCMOS, exact OPN not frozen |
| rebuild FPGA system clock | 125 MHz fixed PLL output |
| sample scheduler | 40-bit fractional accumulator |
| ML history | 3600 s |
| Goertzel AM 3 dB bandwidth | ~15 Hz |
| Goertzel PM 3 dB bandwidth | ~930 Hz |
| PM correlation processing | carrier / 20 = 3.875 kHz |
| PRN chip rate | carrier / 120 = 645.833... Hz |
| PRN length | 512 chips |
| PRN active window | 200 ms to ~992.774 ms |
| PM phase excursion | approximately ±13° in the PTB/Engeler-era description |
| Clock target after discipline | ~0.1 ppm |
| Demonstration-receiver design accuracy | ~1 ms |
| Measured spread of 54 first-sync tests | 362 µs |
| Demonstration receiver operating point | about Eb/N0 > 7.4 dB |
| ML decoder maximum BER after 1 h | about 0.34 |

## Current reconstruction status

### Resolved

- full paper converted into implementation-oriented Markdown;
- source PDF archived away from the repository root;
- DCF77 PM/PZF generator recovered from PTB documentation;
- 512-chip reference generator implemented in Python;
- first LTC1562 77.5 kHz resistor set derived from the manufacturer's 8th-order band-pass application;
- 14-bit LTC1407 family ambiguity narrowed to an `A` variant;
- first analog prototype architecture and bring-up procedure documented;
- ECP5 selected as the rebuild FPGA family, with LFE5U-45F/BG256 as the current Rev.0 target;
- fixed 25 MHz -> 125 MHz ECP5 clock strategy selected;
- 40-bit fractional 930 kS/s scheduler designed and first portable RTL added.

### Still to recover or choose

- exact FTD02011R electrical parameters used by Engeler;
- replacement/front-end topology for the obsolete BF245A;
- original LTC1562 resistor values versus final sustainable filter implementation;
- LTC6912 suffix or replacement PGA;
- final ADC choice and driver;
- exact lifecycle-safe 25 MHz oscillator OPN(s);
- SPI configuration flash and FPGA power-tree parts;
- carrier-discipline loop coefficients and confidence thresholds;
- original PCB/Gerbers and connector details;
- fixed-point constants and final ECP5 resource mapping.

These remaining gaps are tracked in [`docs/09-gaps-and-open-questions.md`](docs/09-gaps-and-open-questions.md).

## First buildable analog proposal

The initial rebuild described in [`docs/11-analog-reference-design.md`](docs/11-analog-reference-design.md) deliberately distinguishes recovered facts from new engineering choices.

Its starting point is:

```text
77.5 kHz ferrite antenna
 -> high-impedance input stage
 -> LTC1562 8th-order band-pass (reference Rev.0 option)
 -> LTC6912 PGA (reference Rev.0 option)
 -> explicit ADC drive/common-mode stage
 -> ~14-16 bit ADC @ 930 kS/s
 -> Lattice ECP5
```

The first-pass LTC1562 target values derived from the 80 kHz manufacturer application are approximately:

```text
RIN1                  4.79 kOhm
RQ1                   47.9 kOhm
R21                   12.8 kOhm
RIN2/RIN3/RIN4        47.9 kOhm
RQ2/RQ3/RQ4           47.9 kOhm
R22/R23/R24           12.8 kOhm
```

This yields an intentionally generous analog bandwidth around 7.75 kHz so the PM sidebands are preserved during initial development.

## PM generator now fully specified

The PTB generator used by DCF77 is reconstructed in [`docs/10-dcf77-pm-prn.md`](docs/10-dcf77-pm-prn.md):

```text
9-stage register
feedback taps 5 XOR 9
polynomial x^9 + x^5 + 1
512 balanced chips
fchip = 77,500 / 120 Hz
start = second + 200 ms
data 1 = inverted sequence
seconds 0-9 = ten inverted sequences for minute identification
```

Run:

```bash
python3 tools/dcf77_prn.py --verify
python3 tools/clock_plan.py
```

to sanity-check both the PM sequence and the current clock plan before implementing/altering the HDL.

## Reconstruction policy

The paper is an architecture/performance paper, **not a complete construction dossier**. This repository therefore labels information by origin:

- facts directly present in Engeler;
- facts recovered from PTB primary sources;
- manufacturer data-sheet facts;
- secondary evidence requiring validation;
- explicit new reconstruction choices.

The goal is to produce a receiver that can actually be rebuilt without silently presenting guessed circuitry as historical fact.

A second rule applies to obsolete silicon: **reproduce the behaviour and measured performance of the Engeler receiver, not the lifecycle problems of its 2012 BOM**.

## Recommended project strategy

Rebuild the system incrementally:

1. characterize/tune the ferrite antenna;
2. validate the input stage and analog band-pass with a signal generator;
3. bring up ECP5 configuration and fixed 125 MHz clocking;
4. validate the fractional 930 kS/s scheduler and capture clean raw ADC data;
5. implement AM/carrier phase detection;
6. close the carrier-based sample-clock discipline loop;
7. validate the 512-chip PM correlator;
8. implement second/minute synchronisation;
9. add the ML time decoder;
10. measure self-interference and final timing performance.

Raw ADC recordings should be retained as regression data so later DSP revisions can be tested without changing the RF environment.