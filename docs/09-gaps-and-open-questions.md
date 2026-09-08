# Gaps and open questions

The paper contains enough information to reproduce the receiver **architecture**, but not enough to clone the original PCB verbatim. This document separates published facts from reconstruction work.

## Missing hardware details

Not published in the paper:

- complete schematic;
- PCB layout/Gerbers;
- ferrite antenna inductance and tuning capacitor;
- BF245A bias and gain network;
- LTC1562 external component values and exact transfer function;
- LTC6912 gain range/table used by the AGC;
- anti-alias/filter inter-stage level plan;
- regulator part numbers and power-tree details;
- oscillator part number/frequency before the FPGA clock manager;
- USB interface device and protocol;
- LCD type/interface;
- DAC use and channel mapping;
- connector pinout and debug header definition.

## Missing DSP/FPGA constants

Not published explicitly:

- HDL/source code;
- fixed-point word widths;
- Goertzel state scaling constants as binary values;
- carrier Goertzel loop bandwidth versus acquisition state;
- CORDIC precision/iteration count;
- exact AGC thresholds and time constants;
- exact second/minute correlation normalisation;
- ML confidence-check thresholds;
- all overflow/saturation rules;
- memory organisation and update schedule;
- detailed random-burst processing algorithm.

## DCF77 PM code dependency

The paper refers to the known **512-bit pseudo-random PM0 pattern** but does not print the sequence/generator definition. The exact pattern must be sourced from the official DCF77 specification or the references cited by Engeler before the PM detector can be considered complete.

This is a hard dependency, not a detail to guess.

## Original clock-tree ambiguity

The paper illustrates a fast clock around 300 MHz and a corrected derived clock around the high-30-MHz range, with a nominal divide factor `d = 8`. The functional correction method is clear, but the exact original oscillator/PLL/DCM frequencies and implementation details are not completely specified in text.

A modern recreation should preserve the **fractional correction principle and final ppm performance**, not blindly copy a rounded frequency label from the figure.

## Analog filter reconstruction

The digital AM and PM paths have reported effective bandwidths (~15 Hz and ~930 Hz), but those are not the required analog BPF bandwidths. The analog front-end must retain enough PM sideband content. Deriving the LTC1562 component values therefore requires a separate filter-design exercise based on:

- 77.5 kHz centre;
- useful DCF77 spectrum up to roughly the first side lobes (~2.583 kHz span discussed in the paper);
- allowed group-delay variation;
- adjacent interference environment;
- ADC anti-alias requirements.

## Confidence-check reconstruction

The paper gives a target wrong-decode probability but not the thresholds that produced it. The ML decoder should therefore be calibrated with Monte-Carlo simulation. Keep the target probability and report the measured false-lock rate for every chosen threshold set.

## Questions to resolve during implementation

1. Can the exact HKW FTD02011R antenna still be obtained, and what are its measured L/Q values?
2. Should the first reproduction use the historical ADC/PGA/filter parts or modern equivalents?
3. Which FPGA family is the target for the new build?
4. Is the goal architectural equivalence, or a museum-faithful copy of the original PCB?
5. What absolute timing accuracy is required: millisecond-class or PM-level tens of microseconds?
6. Which official DCF77 PM specification/version will be the authoritative source for the PRN sequence and special bits?
7. How will false-lock probability be measured and documented?

These questions should be converted into GitHub issues as the implementation starts.
