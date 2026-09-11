# Gaps and open questions

This repository separates three classes of information:

1. facts recovered from Engeler/PTB/manufacturer sources;
2. explicit modern rebuild choices;
3. genuinely unresolved design questions.

## Resolved

### DCF77 PM PRN generator

Resolved from PTB documentation. See [`10-dcf77-pm-prn.md`](10-dcf77-pm-prn.md) and [`../tools/dcf77_prn.py`](../tools/dcf77_prn.py).

### First LTC1562 rebuild filter

A buildable first-pass 77.5 kHz filter has been derived from the manufacturer's published 8th-order application. This is a rebuild design, not recovery of Engeler's exact resistor values. See [`11-analog-reference-design.md`](11-analog-reference-design.md).

### Rebuild FPGA family

The new implementation targets Lattice ECP5, initially `LFE5U-45F/BG256`, while keeping the signal-processing core portable. See [`12-ecp5-migration.md`](12-ecp5-migration.md).

### FPGA resource ceiling

The release design is constrained to the historical XC3S1400AN resource class:

```text
LUT4 equivalents <= 22,528
flip-flops       <= 22,528
EBR/BRAM         <= 576 Kibit / 32 EBR18
18x18 multipliers<= 32
```

See [`16-fpga-resource-budget.md`](16-fpga-resource-budget.md) and [`../rtl/resource_budget.json`](../rtl/resource_budget.json).

### Rebuild hardware CAD

The schematic/PCB source of truth is tscircuit, with KiCad export and independent release review. See [`14-hardware-cad-tscircuit.md`](14-hardware-cad-tscircuit.md).

### Rev.0 board format

Rev.0 is now a single **Raspberry Pi Standard HAT+**. The previously planned standalone USB-C board is removed. See [`17-pcb-variants.md`](17-pcb-variants.md).

## Missing historical hardware details

Still not recovered:

- complete original schematic;
- PCB/Gerbers;
- exact FTD02011R inductance/Q/tuning capacitor on Engeler's unit;
- BF245A topology and bias;
- original LTC1562 resistor values and measured transfer function;
- LTC6912 suffix;
- LTC1407A suffix and ADC-driver details;
- original regulator tree;
- original Xilinx oscillator/clock-tree parts;
- original USB/display/DAC connector details.

The USB item above is a **historical unknown from Engeler's demonstrator**, not a Rev.0 board feature.

## Current reconstruction choices already frozen

- integrated TDK ferrite with fixed no-trim network;
- OPA810 input buffer;
- LTC1562 fixed 77.5 kHz filter;
- LTC6912-1 PGA;
- LTC1407A-1 ADC with OPA2835 driver candidate;
- ECP5 `LFE5U-45F-7BG256I`;
- W25Q64JV flash;
- SiT5356 25 MHz fixed TCXO;
- Raspberry Pi HAT+ power split using both Pi 5 V and 3.3 V;
- dedicated external hardware PPS;
- local 20x2 transflective LCD.

## Missing DSP constants

Resolved — each constant set is now documented in a dedicated decision record
under `docs/decisions/`. See:

- `docs/decisions/dsp-01-fixed-point-word-widths.md` — fixed-point word widths
- `docs/decisions/dsp-02-goertzel-scaling.md` — Goertzel scaling
- `docs/decisions/dsp-03-carrier-loop-bandwidth-schedule.md` — carrier-loop bandwidth schedule
- `docs/decisions/dsp-04-cordic-precision.md` — CORDIC precision (not used; implicit rotation instead)
- `docs/decisions/dsp-05-agc-thresholds-time-constants.md` — AGC thresholds/time constants
- `docs/decisions/dsp-06-correlation-normalization.md` — correlation normalization
- `docs/decisions/dsp-07-ml-confidence-thresholds.md` — ML confidence thresholds
- `docs/decisions/dsp-08-overflow-saturation-policy.md` — overflow/saturation policy
- `docs/decisions/dsp-09-memory-organization.md` — memory organization
- `docs/decisions/dsp-10-randomized-processing-schedule.md` — randomized-processing schedule (deferred)

All constants are implemented as Verilog parameters/localparams in the RTL
modules and verified by simulation (iverilog) and formal proof (SymbiYosys).
Some are calibration constants that must be re-validated once real DCF77
signal captures and hardware noise-floor measurements are available.

## Measurement questions

Before PCB Rev.0 is considered frozen for fabrication, establish:

- actual integrated-antenna L/Q/bandwidth/group delay;
- analog BPF center frequency, bandwidth and group delay;
- Raspberry Pi / FPGA / clock self-interference at 77.5 kHz;
- ADC conversion jitter and analog noise floor;
- desired final absolute timing target;
- required holdover duration and allowed error;
- clock-loop acquisition/tracking coefficients;
- false-lock probability of the ML decoder;
- PI_3V3 current and HAT+ STANDBY behavior.

## Principle

When an unknown is solved by a new design choice, label it **reconstruction**. When it is solved from a primary source or original hardware measurement, label it **recovered fact**.
