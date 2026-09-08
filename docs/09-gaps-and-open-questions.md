# Gaps and open questions

The Engeler paper contains enough information to reproduce the receiver **architecture**, but not enough to clone the original PCB verbatim. This document now distinguishes unresolved questions from items that have been recovered from external primary/manufacturer sources or resolved by explicit rebuild choices.

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

### Rebuild FPGA family — RESOLVED AS A DESIGN CHOICE

The new implementation targets:

```text
Lattice ECP5 LFE5U-45F
BG256 / caBGA256
```

The historical XC3S1400AN remains relevant only as a reference to the original receiver.

See [`12-ecp5-migration.md`](12-ecp5-migration.md).

### Rebuild clock architecture — RESOLVED AT ARCHITECTURE LEVEL

The exact original Xilinx oscillator/DCM implementation is still historically unknown, but the **new ECP5 implementation** is now defined:

```text
25 MHz standard XO
 -> fixed ECP5 PLL
 -> 125 MHz system clock
 -> 40-bit fractional ADC sample scheduler
 -> average 930 kS/s
 -> slow trim from DCF77 carrier phase
```

The first scheduler RTL is in [`../rtl/core/sample_scheduler.sv`](../rtl/core/sample_scheduler.sv). Calculations are reproducible with [`../tools/clock_plan.py`](../tools/clock_plan.py).

See [`13-ecp5-clock-discipline.md`](13-ecp5-clock-discipline.md).

This resolves the implementation architecture, **not** the exact loop coefficients or final oscillator manufacturer OPN.

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
- original oscillator part number/frequency before the Xilinx clock manager;
- USB interface device and protocol;
- LCD type/interface;
- DAC use and channel mapping;
- connector pinout and debug-header definition.

These remain historical unknowns even where the rebuild deliberately chooses a modern replacement architecture.

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

## Rebuild clock items still open

The ECP5 architecture is fixed, but several implementation details still require validation:

- select at least two lifecycle-safe 25 MHz oscillator OPNs;
- generate and verify the final ECP5 PLL primitive parameters with the selected toolchain;
- select acquisition/tracking loop coefficients;
- select phase-outlier/hole-punch thresholds;
- establish holdover/reacquisition confidence rules;
- measure actual ADC `CONV` timing quantisation/jitter;
- measure self-interference caused by 25 MHz, 125 MHz and the fractional conversion pattern.

These are tuning/validation tasks, not reasons to reopen the basic fixed-PLL/fractional-scheduler architecture unless measurements show a concrete failure.

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
2. Which modern high-impedance input stage should replace the obsolete BF245A in the sustainable BOM?
3. Which LTC6912 variant, or replacement PGA, should be frozen in the BOM?
4. Which ADC should be frozen for the rebuild and what driver/common-mode circuit does it require?
5. Which two approved 25 MHz XO sources will be used for lifecycle resilience?
6. What absolute timing target will define success: ~1 ms, <100 µs, or carrier-cycle-level timing?
7. How will ferrite-antenna group delay be calibrated?
8. How will FPGA/USB/display self-interference be measured before enclosure design?
9. What raw DCF77 capture corpus will be stored for DSP regression testing?
10. How will ML false-lock probability be measured and documented?
11. What clock-loop coefficients provide fast acquisition without following impulsive phase noise?

These questions should become GitHub issues as component sourcing, board design and RTL validation progress.

## Principle for future documentation

When an unknown is solved by a **new design choice**, label it as reconstruction. When it is solved from a **primary source, manufacturer data sheet, original photograph or original hardware measurement**, label it as recovered fact. This distinction is essential if the repository is to remain useful both as an engineering project and as a faithful reconstruction record.