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

## Clock-source selection — OPEN BY DESIGN

The clock-control architecture is understood, but **no SiTime OPN or nominal frequency is frozen**.

The earlier SiT5348 at 24.18 MHz proposal is now only an arithmetic/architecture study.

Selection must be based on:

- synchronized timing target;
- holdover duration/error;
- exact Digi-Key/Mouser/manufacturer availability;
- temperature range;
- DCTCXO pull range and control method;
- ECP5 PLL legality;
- sample-clock implementation;
- EMI/self-interference around 77.5 kHz;
- lifecycle and cost.

Current baseline: evaluate stocked SiTime DCTCXO parts around the ±100 ppb class at standard catalogue frequencies, notably 10, 25 and 26 MHz. See [`15-sitime-super-tcxo.md`](15-sitime-super-tcxo.md).

The generic fractional scheduler remains valid regardless of the chosen frequency:

- [`../rtl/core/sample_scheduler.sv`](../rtl/core/sample_scheduler.sv)

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
- USB/display/DAC connector details.

These remain historical unknowns even where the rebuild deliberately uses replacements.

## Rebuild hardware choices still open

1. sustainable high-impedance input stage replacing BF245A;
2. final analog-filter implementation: LTC1562 reference path versus modern op-amp equivalent;
3. PGA selection;
4. final SAR ADC and driver/common-mode stage;
5. final DCTCXO OPN and frequency;
6. ECP5 configuration flash;
7. low-noise power tree;
8. ferrite antenna part and mechanical arrangement.

## Missing DSP constants

Still to reconstruct and validate:

- fixed-point word widths;
- Goertzel scaling;
- carrier-loop bandwidth schedule;
- CORDIC precision if used;
- AGC thresholds/time constants;
- correlation normalization;
- ML confidence thresholds;
- overflow/saturation policy;
- memory organization;
- randomized-processing schedule.

These must be solved by simulation plus regression against stored DCF77 captures.

## Measurement questions

Before schematic/PCB Rev.0 is considered frozen, establish:

- actual antenna L/Q/bandwidth/group delay;
- analog BPF center frequency, bandwidth and group delay;
- FPGA/clock/USB self-interference at 77.5 kHz;
- ADC conversion jitter and analog noise floor;
- desired final absolute timing target;
- required holdover duration and allowed error;
- clock-loop acquisition/tracking coefficients;
- false-lock probability of the ML decoder.

## Principle

When an unknown is solved by a new design choice, label it **reconstruction**. When it is solved from a primary source or original hardware measurement, label it **recovered fact**.
