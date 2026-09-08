# Hardware reconstruction

This document separates three things that must not be confused:

1. **parts explicitly named by Engeler**;
2. **facts recoverable from manufacturer/PTB documentation**;
3. **engineering choices made by this repository to produce a buildable first prototype**.

The detailed first-pass circuit proposal is in [`11-analog-reference-design.md`](11-analog-reference-design.md).

## Published component inventory

The demonstration receiver block diagram identifies the following parts explicitly:

| Function | Part / specification in paper | Reconstruction status |
|---|---|---|
| ferrite antenna | HKW FTD02011R | exact reference named; detailed electrical data still to be measured/recovered |
| antenna input device | BF245A JFET | exact family named; original bias network unknown |
| analog band-pass | LTC1562, 8th-order filter | exact IC named; original resistor values unknown |
| programmable gain | LTC6912 PGA | exact family named; `-1` vs `-2` suffix unknown |
| ADC | LTC1407 family, labelled 14 bit, 930 kS/s | 14-bit member must be an `A` variant; exact suffix unknown |
| FPGA | Xilinx XC3S1400AN | exact family/device named |
| debug DAC | LTC2624, 4 channel | exact family named; channel mapping unknown |
| history memory | 3600 s logical history | FPGA implementation detail |
| user output | LCD | type/interface unknown |
| debug/control | USB plus internal debug path | interface device/protocol unknown |
| reference clock | oscillator | exact oscillator unknown |

## Important ADC part-number clarification

Analog Devices documents the family as follows:

- `LTC1407` / `LTC1407-1`: 12-bit;
- `LTC1407A` / `LTC1407A-1`: 14-bit.

Engeler's block diagram uses the shortened label **LTC1407** while explicitly stating **14 bit**. Therefore this repository records the historical fact as “LTC1407 family, 14-bit A variant” until a photograph/BOM of the original board establishes the suffix.

For a new build, [`11-analog-reference-design.md`](11-analog-reference-design.md) currently recommends `LTC1407A-1` because its bipolar differential span is convenient for an AC receiver signal.

## Ferrite antenna requirements

The antenna is resonant and high impedance. The paper also notes that tuned ferrite antennas can have significant resonant-frequency tolerance, which directly affects group delay and absolute PM timing.

The original paper does **not** provide:

- exact coil inductance;
- exact resonating capacitor value;
- ferrite permeability/material;
- winding resistance;
- Q;
- tap/coupling arrangement;
- mechanical spacing to the PCB.

A secondary comparison based on HKW antenna data reports approximately 897 µH and about 700 Hz bandwidth for several HKW DCF77 ferrite rods. This is useful only as a prototype starting point and must not be assumed to be the exact FTD02011R value.

If `L ~= 897 µH`, resonance at 77.5 kHz requires about `C ~= 4.70 nF`. Measure the actual antenna before fixing this value.

## BF245A input stage

NXP identifies the BF245A as a general-purpose N-channel JFET. The A grade has a broad device spread, including approximately 2 to 6.5 mA `IDSS`, so a copied fixed bias network would be risky even if one were guessed.

The paper does not publish:

- source/drain resistor values;
- operating current;
- topology (source follower versus common-source details);
- exact gain;
- ESD/protection network.

For the first rebuild, use the high-impedance source-follower starting point documented in `11-analog-reference-design.md`, measure several devices, and only then freeze the bias network.

## LTC1562 analog band-pass

This part is now much better constrained than in the first version of this documentation.

Analog Devices publishes a directly relevant **8th-order high-frequency band-pass** application using all four LTC1562 sections. The example has:

```text
-3 dB bandwidth = center frequency / 10
overall gain = 10
```

The nearest published table entry is 80 kHz. Scaling the resistor network by `80/77.5` gives a credible first prototype at the DCF77 carrier:

| Resistor group | 77.5 kHz calculated target |
|---|---:|
| `RIN1` | 4.79 kOhm |
| `RQ1` | 47.9 kOhm |
| `R21` | 12.8 kOhm |
| `RIN2`, `RIN3`, `RIN4` | 47.9 kOhm |
| `RQ2`, `RQ3`, `RQ4` | 47.9 kOhm |
| `R22`, `R23`, `R24` | 12.8 kOhm |

This produces a first-pass analog bandwidth around **7.75 kHz**, intentionally much wider than the digital AM path.

PTB documentation shows that preserving only the main PRN spectral lobe already calls for approximately **1.292 kHz** total receive bandwidth. Therefore the analog BPF must preserve PM sidebands; it must not be designed from the ~15 Hz AM Goertzel bandwidth.

The values above are **reconstruction values derived from the manufacturer application circuit**, not recovered original Engeler values.

## LTC6912 PGA

Analog Devices lists two variants:

- `LTC6912-1`: gains 0, 1, 2, 5, 10, 20, 50, 100 V/V;
- `LTC6912-2`: gains 0, 1, 2, 4, 8, 16, 32, 64 V/V.

The paper does not state which one is populated. The rebuild currently prefers `LTC6912-1` for its higher maximum gain, but the FPGA interface should isolate this choice so either table can be used.

The AGC should respond to ADC headroom, not to the intentional 100/200 ms DCF77 amplitude dip. Start with manual gain control during hardware bring-up.

## ADC interface

The target sample rate is:

```text
930 kS/s = 12 * 77.5 kHz
```

This exact integer relationship is central to the Engeler architecture: one carrier cycle corresponds to 12 ADC samples in the nominal clock domain.

For the 14-bit 2.5 V span, one LSB is about 153 µV. The paper's weak-signal design point of only a few ADC LSBs therefore requires careful analog noise control.

The LTC1407A family has differential sample-and-hold inputs. Manufacturer guidance recommends low source impedance and a fast settling driver. Because the original block diagram does not identify a separate driver, the first rebuild makes this interface explicit and treats it as a reconstruction addition.

## FPGA functional blocks to recreate

The paper's block diagram identifies these digital functions:

- random sample-processing delay/buffering;
- automatic gain control;
- phase detection;
- clock synchronisation;
- PM/AM correlation;
- correlation accumulation;
- second detection;
- second synchronisation;
- 3600 s history storage;
- time decoding;
- debug capture/output;
- LCD interface;
- DAC debug outputs;
- USB interface.

The exact FPGA partitioning and buses are not published. A modern implementation should separate the design into:

- high-rate sample/phase processing;
- chip-rate PM correlation;
- one-second statistics/synchronisation;
- slow control/AGC;
- time decoder/history memory;
- clock discipline.

## PRN dependency: resolved

The exact DCF77 PM generator is now documented in [`10-dcf77-pm-prn.md`](10-dcf77-pm-prn.md), with a reference generator in [`../tools/dcf77_prn.py`](../tools/dcf77_prn.py).

Recovered facts include:

- 9-stage register;
- feedback taps 5 and 9;
- equivalent polynomial `x^9 + x^5 + 1`;
- 512 balanced chips;
- chip rate `77.5 kHz / 120`;
- cycle start at +200 ms;
- sequence inversion for logical 1;
- ten inverted cycles in seconds 0-9 as PM minute identifier.

## Prototype power-tree recommendation

The original regulator tree is unknown. A clean rebuild can start with:

```text
5V_A   -> BF245A, LTC1562, LTC6912
3V0_A  -> LTC1407A-1
3V3_D  -> digital I/O as required
FPGA core rails -> selected FPGA requirements
```

The analog rails should be low-noise. Avoid putting a switching converter, display driver or USB clock near the ferrite antenna.

## Mandatory hardware debug points

The first PCB should expose:

- antenna node (high impedance);
- JFET output;
- band-pass output;
- PGA output;
- ADC input;
- ADC `CONV`, `SCK`, and serial data;
- analog ground/reference;
- one FPGA debug output;
- optional DAC debug channels.

A receiver this sensitive is much easier to debug if every stage can be validated without relying on the final time decoder.

## Reference BOM versus rebuild BOM

This repository tracks two concepts:

### Historical/reference BOM

Use the exact parts named in the paper where the purpose is to reproduce the 2012 demonstrator as closely as possible.

### Rebuild BOM

Use obtainable parts and explicit interface specifications where exact historical parts are unavailable. Any substitution must preserve:

- high input impedance at the ferrite antenna;
- sufficient low-frequency noise performance;
- at least the PM signal bandwidth;
- controllable wide gain range;
- approximately 14-bit ADC resolution;
- deterministic 930 kS/s timing or a carefully adapted equivalent;
- FPGA resources sufficient for correlation and 3600 s history.

## Next hardware deliverable

The next milestone after validating this reference design is a **KiCad schematic revision 0** with:

1. measured antenna parameters;
2. simulated/measured LTC1562 response;
3. selected PGA suffix;
4. selected ADC suffix and driver;
5. final analog power rails;
6. test-point and connector plan.

Until those measurements are available, the repository should not pretend that a guessed schematic is the original Engeler board.