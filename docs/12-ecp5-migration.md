# ECP5 migration target

## Platform decision

The rebuild targets:

```text
Lattice ECP5
LFE5U-45F
BG256 / caBGA256
```

The plain `LFE5U` family is preferred because the receiver does not require SERDES.

BG256 remains attractive for the first board because its 0.8 mm pitch is practical and supports density migration where pin compatibility permits.

## Important rule: physical capacity is not the design budget

The 45F contains substantially more logic/DSP/RAM than the historical XC3S1400AN. The rebuild is **not allowed to use that extra capacity as part of the claimed receiver implementation**.

The `release_reference` synthesis profile must satisfy the historical resource ceiling documented in:

- [`16-fpga-resource-budget.md`](16-fpga-resource-budget.md)
- [`../rtl/resource_budget.json`](../rtl/resource_budget.json)

Core release limits:

```text
LUT4 equivalents <= 22,528
flip-flops       <= 22,528
EBR18            <= 32
block RAM        <= 576 Kibit
18x18 multipliers<= 32
```

The spare 45F resources may be used only by a separate `lab_debug` profile for temporary instrumentation, raw-capture FIFOs or experimental detector variants. Those resources must not be required to reproduce the receiver's advertised performance.

This makes the ECP5-45F a maintainable implementation platform, not an excuse to change the computational scale of Engeler's work.

## Configuration difference

The historical Spartan-3AN integrates nonvolatile configuration memory. ECP5 is SRAM-based, so the board needs an external SPI configuration flash.

Recommended structure:

```text
SPI NOR -> ECP5 Master SPI
JTAG header -> ECP5 JTAG
```

JTAG recovery must remain available even when a USB/JTAG bridge is fitted.

## Power rails

Plan explicitly for:

```text
VCC      1.1 V core
VCCAUX   2.5 V
VCCIOx   selected per bank/interface
```

Switching regulators, FPGA clocking and configuration activity must be physically separated from the ferrite/input section because self-interference at 77.5 kHz is a first-class design constraint.

## Clock abstraction

Do not reproduce Xilinx DCM primitives directly.

The portable core should see abstract timing services such as:

```text
sample_ce
sample position
carrier phase position
second phase
clock-discipline control/status
```

The final oscillator frequency/OPN is intentionally not frozen yet; see [`15-sitime-super-tcxo.md`](15-sitime-super-tcxo.md).

The generic fractional scheduler in [`../rtl/core/sample_scheduler.sv`](../rtl/core/sample_scheduler.sv) allows use of normal stocked oscillator frequencies while preserving the nominal 930 kS/s sample rate.

## DSP architecture remains Engeler-like

```text
ADC @ nominal 930 kS/s
 -> carrier/phase detector
 -> AM observable
 -> PM observable
 -> PRN correlator
 -> second/minute synchronization
 -> 3600 s history
 -> ML time decoder
 -> disciplined local time
```

Resource optimization is part of the implementation requirement. If a clear first version exceeds the historical budget, it must be restructured or time-shared without sacrificing measured performance.

## HDL organization

```text
rtl/core/       vendor-neutral DCF77 algorithms
rtl/platform/   clock/reset/interface abstractions
rtl/ecp5/       ECP5 primitives and board wrappers
```

The detector core must remain simulatable without ECP5 primitives.

## Toolchain

Primary reproducible flow:

```text
Yosys
 -> nextpnr-ecp5
 -> Project Trellis
```

Keep Lattice Diamond as a vendor-reference flow for device-specific validation and timing comparison.

The `release_reference` build should eventually parse synthesis/utilization reports and enforce `rtl/resource_budget.json` automatically.

## Memory policy

Long 930 kS/s raw captures do not belong in the release FPGA memory budget. Stream them off-board.

Use EBR for compact operational state:

- ADC FIFOs;
- detector state;
- correlator state;
- soft-bit/history memory;
- small debug snapshots.

## Bring-up order

1. configuration flash + JTAG recovery;
2. rails and oscillator;
3. clock/PPS test output;
4. ADC capture and host streaming;
5. carrier/phase extraction;
6. AM path;
7. PRN correlation;
8. second/minute synchronization;
9. 3600-second ML decoder;
10. clock discipline;
11. self-interference characterization;
12. confirm `release_reference` meets historical resource limits.

## Lifecycle strategy

- use exact manufacturer OPNs in the BOM;
- keep core HDL vendor-neutral;
- keep SPI NOR generic where possible;
- retain 25F/45F migration options when pinout permits;
- archive known-good open-source toolchain versions;
- monitor Lattice PCNs before board revisions/production;
- never let a larger replacement FPGA silently increase the accepted receiver resource budget.
