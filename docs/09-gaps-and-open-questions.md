# Gaps and open questions

The Engeler paper contains enough information to reproduce the receiver **architecture**, but not enough to clone the original PCB verbatim. This document now distinguishes unresolved questions from items that have been recovered from external primary/manufacturer sources.

## Resolved since the initial documentation pass

### DCF77 PM PRN generator — RESOLVED

The exact PM generator is no longer an open dependency.

PTB documentation provides:

- 9-stage feedback shift register;
- feedback from stages 5 and 9;
- equivalent polynomial `x^9 + x^5 + 1`;
- forced escape from the all-zero state;
- 512 balanced chips per second;
- chip clock `77.5 kHz / 120`;
- cycle start 200 ms after the second boundary;
- sequence inversion keying for binary 1;
- ten inverted cycles during seconds 0-9 as the PM minute identifier.

See [`10-dcf77-pm-prn.md`](10-dcf77-pm-prn.md) and [`../tools/dcf77_prn.py`](../tools/dcf77_prn.py).

### First LTC1562 component set — RESOLVED AS A REBUILD DESIGN

The original Engeler resistor values remain unknown, but the LTC1562 manufacturer data sheet includes a directly applicable 8th-order band-pass topology. Scaling the published 80 kHz design to 77.5 kHz produces a documented, buildable first-pass filter.

This does **not** recover the original PCB values; it resolves the question “how do we build a credible first prototype?”

See [`11-analog-reference-design.md`](11-analog-reference-design.md).

### ADC 14-bit family member — PARTIALLY RESOLVED

The paper labels the part “LTC1407, 14 bit”. Manufacturer data establishes that the 14-bit versions are LTC1407A-family parts. The exact original suffix (`A` versus `A-1`) is still unknown.

## Missing historical hardware details

Still not published/recovered:

- complete original schematic;
- PCB layout/Gerbers;
- exact FTD02011R inductance/Q/tuning capacitor on Engeler's board;
- exact BF245A topology and bias values;
- original LTC1562 resistor values and measured transfer function;
- exact LTC6912 suffix and gain table used;
- exact LTC1407A suffix;
- analog inter-stage level plan;
- ADC driver details, if any separate driver was used;
- regulator part numbers and power-tree details;
- oscillator part number/frequency before the FPGA clock manager;
- USB interface device and protocol;
- LCD type/interface;
- DAC use and channel mapping;
- connector pinout and debug-header definition.

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

These can be reconstructed by simulation and regression against stored RF captures, but they should be documented as new implementation choices.

## Original clock-tree ambiguity

The paper illustrates a fast clock around 300 MHz and a corrected derived clock around the high-30-MHz range, with a nominal divide factor `d = 8`. The functional correction method is clear, but the exact oscillator/PLL/DCM frequencies and implementation details are not completely specified in text.

A modern recreation should preserve the **fractional correction principle and final ppm performance**, not blindly copy a rounded frequency label from the figure.

## Antenna identification and characterization

The exact HKW part is named, but detailed electrical data for the exact Engeler sample is not yet secured.

Before freezing the analog schematic, measure or obtain:

- inductance at 77.5 kHz;
- winding resistance;
- Q and -3 dB bandwidth;
- resonance versus tuning capacitance;
- temperature coefficient;
- resonance shift when mounted on/near the PCB;
- phase/group delay around 77.5 kHz.

A secondary source reports about 897 µH for several HKW DCF77 rods, giving a nominal tuning capacitance near 4.70 nF, but this must remain a provisional value.

## Analog filter validation

The first rebuild filter now has calculated values, but it still needs measurement.

Validate:

- actual centre frequency;
- -3 dB bandwidth;
- passband gain;
- phase/group delay;
- tolerance over temperature;
- rejection of likely local switch-mode interference;
- PM correlation loss relative to a wider raw capture.

Only after those measurements should the filter be considered final.

## Confidence-check reconstruction

The paper gives a target wrong-decode probability but not the thresholds that produced it. The ML decoder should therefore be calibrated with Monte-Carlo simulation. Keep the target probability and report the measured false-lock rate for every chosen threshold set.

## Questions to resolve during implementation

1. Can an authentic HKW FTD02011R be obtained and measured?
2. Is the goal a historically faithful parts build, or an architecture-faithful modern board?
3. Which FPGA family will be used for the first functioning prototype?
4. Which LTC6912 variant should be frozen in the BOM?
5. Which LTC1407A variant best matches the original electrical interface?
6. What absolute timing target will define success: ~1 ms, <100 µs, or carrier-cycle-level timing?
7. How will ferrite-antenna group delay be calibrated?
8. How will FPGA/USB/display self-interference be measured before enclosure design?
9. What raw DCF77 capture corpus will be stored for DSP regression testing?
10. How will ML false-lock probability be measured and documented?

These questions should become GitHub issues once component sourcing and FPGA choice begin.

## Principle for future documentation

When an unknown is solved by a **new design choice**, label it as reconstruction. When it is solved from a **primary source, manufacturer data sheet, original photograph or original hardware measurement**, label it as recovered fact. This distinction is essential if the repository is to remain useful both as an engineering project and as a faithful reconstruction record.