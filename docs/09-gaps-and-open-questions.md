# Gaps and open questions

The Engeler paper contains enough information to reproduce the receiver **architecture**, but not enough to clone the original PCB verbatim. This document distinguishes historical unknowns from items resolved by primary/manufacturer sources or explicit rebuild choices.

## Resolved since the initial documentation pass

### DCF77 PM PRN generator — RESOLVED

The exact PM generator is documented from PTB material and implemented in [`../tools/dcf77_prn.py`](../tools/dcf77_prn.py).

See [`10-dcf77-pm-prn.md`](10-dcf77-pm-prn.md).

### First LTC1562 component set — RESOLVED AS A REBUILD DESIGN

The original Engeler values remain unknown, but a buildable 77.5 kHz first-pass filter was derived from the manufacturer's published 8th-order LTC1562 application.

See [`11-analog-reference-design.md`](11-analog-reference-design.md).

### Historical ADC family clarification — PARTIALLY RESOLVED

The paper labels “LTC1407, 14 bit”. Manufacturer data establishes that the 14-bit parts are LTC1407A-family devices. Exact historical suffix remains unknown.

### Rebuild FPGA — RESOLVED AS A DESIGN CHOICE

```text
Lattice ECP5 LFE5U-45F
BG256 / caBGA256
```

See [`12-ecp5-migration.md`](12-ecp5-migration.md).

### Rebuild hardware CAD — RESOLVED AS A DESIGN CHOICE

The schematic and PCB will be authored in **tscircuit**, with KiCad export/review before fabrication. AI/cloud placement/routing is permitted after hard RF/EMI placement constraints are applied.

See [`14-hardware-cad-tscircuit.md`](14-hardware-cad-tscircuit.md) and [`../hardware/tscircuit/README.md`](../hardware/tscircuit/README.md).

### Rebuild oscillator family and nominal frequency — RESOLVED AT ARCHITECTURE LEVEL

Preferred clock source:

```text
SiTime SiT5348 Super-TCXO / DCTCXO
24.180000 MHz
3.3 V
LVCMOS
I2C frequency control
```

The exact manufacturer ordering code is still to be generated/validated before BOM freeze.

24.18 MHz was selected because it is exactly:

```text
312 * 77.5 kHz
26 * 930 kHz
```

With an ECP5 x5 PLL the system clock is 120.9 MHz and ADC timing is an exact `/130`.

See [`15-sitime-super-tcxo.md`](15-sitime-super-tcxo.md).

### Rebuild clock discipline — RESOLVED AT ARCHITECTURE LEVEL

The preferred hardware loop now disciplines the SiT5348 itself over I2C from DCF77 carrier phase. The ECP5 PLL remains fixed.

The generic 25 MHz + 125 MHz + 40-bit fractional scheduler architecture remains as a fallback/reference path, with RTL in [`../rtl/core/sample_scheduler.sv`](../rtl/core/sample_scheduler.sv).

See [`13-ecp5-clock-discipline.md`](13-ecp5-clock-discipline.md).

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

These remain historical unknowns even where the rebuild chooses a modern substitute.

## Missing DSP/FPGA constants

Not published explicitly:

- HDL/source code;
- fixed-point word widths;
- Goertzel state scaling constants as binary values;
- carrier estimator bandwidth versus acquisition state;
- CORDIC precision/iteration count;
- exact AGC thresholds and time constants;
- exact second/minute correlation normalization;
- ML confidence thresholds;
- overflow/saturation rules;
- memory organization and update schedule;
- detailed randomized/burst processing algorithm.

These can be reconstructed through software models, simulation and regression against stored RF captures.

## Rebuild clock items still open

The architecture is fixed, but implementation/tuning remains:

- generate/validate the exact SiT5348 24.180000 MHz DCTCXO OPN;
- decide low-g versus ultra-low-g option and temperature grade;
- generate and verify the ECP5 24.18 -> 120.9 MHz PLL primitive parameters;
- implement the exact `/130` ADC event generator;
- implement SiT5348 I2C frequency-control RTL/firmware;
- select acquisition/tracking loop coefficients;
- select phase-outlier/hole-punch thresholds;
- establish holdover/reacquisition confidence rules;
- measure TCXO/PLL/ADC timing jitter on hardware;
- measure self-interference caused by the harmonically related 24.18/120.9 MHz clocks.

The older fractional scheduler remains available if the DCTCXO path fails a real measurement or sourcing requirement.

## Antenna characterization

Before the analog design is frozen, obtain/measure:

- inductance at 77.5 kHz;
- winding resistance;
- Q and -3 dB bandwidth;
- resonance versus tuning capacitance;
- temperature coefficient;
- mounting-induced resonance shift;
- phase/group delay around 77.5 kHz.

A provisional ~897 µH figure from secondary HKW data implies ~4.70 nF tuning near 77.5 kHz, but it must not be treated as the exact Engeler antenna value.

## Analog filter validation

Validate the first rebuild filter for:

- centre frequency;
- -3 dB bandwidth;
- passband gain;
- phase/group delay;
- temperature/tolerance sensitivity;
- rejection of realistic switch-mode interference;
- PM correlation loss versus a wider raw capture.

## Hardware CAD validation still required

Selecting tscircuit does not finish the board design.

Still required:

- pin-accurate component wrappers and footprints;
- complete netlist;
- board dimensions/mechanical requirements;
- analog/digital/RF keepout zones;
- ECP5 BG256 fanout strategy;
- power/ground strategy;
- placement checks before routing;
- AI/cloud routing evaluation;
- KiCad export review and independent DRC;
- fabrication-release archive.

Because tscircuit/KiCad conversion is evolving, exporter output must always be reviewed rather than assumed perfect.

## Confidence-check reconstruction

The paper gives a wrong-decode target but not the thresholds that produced it. The ML decoder must therefore be calibrated with Monte-Carlo simulation and real captures, with false-lock probability recorded for every threshold set.

## Current questions to resolve

1. Can an authentic HKW FTD02011R be obtained and characterized?
2. Which modern high-impedance input stage replaces the obsolete BF245A?
3. Which sustainable band-pass implementation becomes the final BOM: LTC1562 reference design or standard-op-amp biquads?
4. Which PGA becomes final?
5. Which SAR ADC and driver/common-mode stage become final?
6. Which exact SiT5348 DCTCXO OPN should be ordered for Rev.0?
7. Which ECP5 speed/temperature OPN and SPI configuration flash should be frozen?
8. Which regulators satisfy both lifecycle and receiver-noise requirements?
9. What absolute timing target defines final success: ~1 ms, <100 µs, or better?
10. How will ferrite-antenna group delay be calibrated?
11. What raw DCF77 capture corpus will be kept for regression?
12. What carrier-loop coefficients give fast acquisition without following propagation/impulse noise?
13. How will FPGA/TCXO/USB/display self-interference be measured and accepted?
14. How will ML false-lock probability be measured and documented?

## Documentation principle

When an unknown is solved by a **new design choice**, label it as reconstruction. When it is solved from a **primary source, manufacturer data sheet, original photograph or original hardware measurement**, label it as recovered fact.

That distinction is essential for keeping the repository both buildable and historically honest.
