# ECP5 migration target

## Decision

The historical Xilinx XC3S1400AN is not the implementation target for the rebuild.

The current preferred FPGA for the first custom PCB is:

```text
Lattice ECP5
LFE5U-45F
caBGA256 (BG256)
industrial grade preferred when sourcing permits
```

The exact speed/temperature suffix will be frozen when the production BOM is sourced. The HDL must remain portable across at least the ECP5 25F and 45F densities where practical.

This choice changes the FPGA implementation platform, not the Engeler signal-processing architecture.

## Why the 45F

The receiver does not need SERDES, PCIe or multi-gigabit transceivers, so the plain `LFE5U` family is preferred over `LFE5UM`/`LFE5UM5G`.

The 45F provides approximately:

- 44K LUTs;
- 108 embedded 18-kbit RAM blocks, about 1.944 Mbit total EBR;
- 72 18 x 18 multipliers;
- four PLLs and four DLLs;
- the BG256 option with up to 197 user I/O in the plain ECP5 family.

This is substantially more DSP and memory capacity than the DCF77 datapath needs and deliberately leaves margin for instrumentation, raw-data capture FIFOs, confidence metrics and experimental detector variants.

A 25F may eventually be sufficient for a cost-reduced version. The 25F has about 24K LUTs, 56 18-kbit EBRs and 28 18 x 18 multipliers. The first implementation should use 45F so resource optimisation does not obscure algorithm validation.

## Package choice: BG256

Use `BG256` for the custom board unless later sourcing changes the decision.

Reasons:

- 14 x 14 mm package;
- 0.8 mm ball pitch;
- available for LFE5U-25F and LFE5U-45F;
- much easier PCB fan-out than the 10 x 10 mm, 0.5 mm-pitch MG285 package;
- enough I/O for ADC, PGA, debug, USB bridge, optional LCD and expansion.

Before freezing the PCB, validate all selected pins against Lattice's official caBGA256 migration/pinout files. The board should avoid density-specific pins where that would prevent a 25F/45F population option.

## Important difference from Spartan-3AN: configuration memory

The XC3S1400AN belongs to a family with integrated nonvolatile configuration storage. ECP5 is SRAM-based.

The rebuild therefore needs an **external SPI configuration flash**.

Recommended architecture:

```text
SPI NOR flash
    |
    +--> ECP5 Master SPI configuration port

JTAG header --> ECP5 JTAG
```

Keep the native JTAG header accessible even if a USB/JTAG bridge is fitted. The SPI flash should be in-circuit programmable, and the PCB should permit recovery from an invalid image.

The ECP5 configuration logic supports external SPI PROM operation and dual/quad read modes. Configuration starts at a nominal low MCLK frequency and can switch to a higher configured rate later in the boot stream.

## Power rails added by ECP5

The FPGA power tree must explicitly provide:

```text
VCC      = 1.1 V   core
VCCAUX   = 2.5 V   auxiliary
VCCIOx   = chosen per I/O bank, typically 3.3 V or 2.5 V here
```

The ADC/PGA interface bank voltage must be selected from the actual electrical levels of the final ADC/PGA choices rather than assuming 3.3 V everywhere.

Because the receiver is extremely sensitive to self-interference, FPGA regulators and their switching nodes must be physically separated from the ferrite antenna and first analog stage. Prefer low-noise post-regulation or carefully filtered rails where switching regulators are unavoidable.

## Clock architecture

The Engeler implementation relies on an exact nominal relationship:

```text
fADC = 930 kS/s = 12 * 77.5 kHz
```

The ECP5 clock tree must preserve that invariant.

Do not couple the DSP design to the historical Xilinx DCM implementation. Instead expose a clock-control abstraction with at least:

- a stable board reference oscillator;
- an ECP5 PLL-generated processing clock;
- a deterministic 930 kHz ADC conversion/sample timing domain;
- a numerically or fractionally corrected timebase for carrier discipline;
- clean clock-domain crossings into USB/debug logic.

Lattice currently documents dedicated sysCLOCK PLL/DLL resources for ECP5. The exact discipline mechanism should be designed around measurable output phase/frequency behaviour rather than reproducing Xilinx-specific primitives.

## DSP mapping

The logical pipeline remains:

```text
ADC @ 930 kS/s
  -> carrier / phase detector
  -> AM observable
  -> PM observable
  -> PRN correlator @ 645.833... chips/s
  -> second statistics
  -> second/minute synchronisation
  -> 3600 s history
  -> maximum-likelihood time decoder
  -> disciplined local time
```

### Multipliers

The ECP5 45F has enough 18 x 18 multipliers that the first design should favour clarity over aggressive resource sharing.

Recommended policy:

1. infer or instantiate DSP multipliers for the high-rate Goertzel/mixer paths;
2. pipeline operations so timing closure is easy;
3. time-share only after a working reference implementation exists;
4. keep a pure behavioural/reference model in software for bit-accurate regression.

### Memory

Do **not** store long raw 930 kS/s captures in ECP5 EBR.

Use EBR for:

- ADC FIFOs;
- Goertzel/correlation state;
- one-second accumulators;
- PRN tables if a generated LFSR is not used;
- the 3600-second soft/history dataset;
- debug snapshots.

Long raw captures should stream to a host or external RAM.

## HDL portability rules

The receiver HDL should not become ECP5-only at the algorithm level.

Use three layers:

```text
rtl/core/       vendor-neutral DCF77 algorithms
rtl/platform/   clock/reset/IO abstractions
rtl/ecp5/       ECP5 primitives and board-specific wrappers
```

Vendor primitives are acceptable in `rtl/ecp5/` for PLLs, EBRs, DSP blocks or special I/O, but the core detector must remain simulatable without them.

## Toolchain

Two flows are useful:

### Reproducible open-source flow

```text
Yosys
  -> nextpnr-ecp5
  -> Project Trellis bitstream tools
```

Upstream nextpnr describes ECP5 support through Project Trellis as stable. This should be the default CI/synthesis path where the required primitives are supported.

### Vendor flow

Keep Lattice Diamond available as a reference flow for:

- timing comparison;
- PLL configuration/verification;
- device-specific primitives;
- checking edge cases not modelled by the open-source flow.

Do not require proprietary IP for the DCF77 core algorithms.

## Proposed top-level interfaces

The first ECP5 board/RTL boundary should expose approximately:

```text
# ADC
adc_conv
adc_sck
adc_sdo_a
adc_sdo_b        # if final ADC is dual channel

# PGA
pga_cs
pga_sck
pga_mosi

# configuration/debug
jtag_tck
jtag_tms
jtag_tdi
jtag_tdo
uart_tx/rx or USB bridge FIFO

# time/debug
pps_out
carrier_lock
second_lock
minute_lock

# optional
lcd/spi display
external trigger
raw capture trigger
```

Exact pins belong in the board constraint file, not the detector RTL.

## Bring-up order on ECP5

1. boot from SPI flash and verify JTAG recovery;
2. validate all power rails and oscillator;
3. produce a clean test clock/PPS output;
4. capture ADC samples into a small FIFO and stream them to the host;
5. implement carrier Goertzel/phase extraction;
6. add AM processing;
7. port the verified 512-chip PRN generator/correlator;
8. add second/minute synchronisation;
9. add the 3600-second ML decoder;
10. implement carrier-based clock discipline;
11. measure FPGA self-interference at the ferrite antenna and add randomised processing scheduling if required.

## Lifecycle strategy

Choosing ECP5 does not eliminate lifecycle risk; it moves the project to a currently maintained and widely used platform.

For durability:

- use the non-SERDES `LFE5U` unless a real transceiver requirement appears;
- design the BG256 footprint/pin assignment for 25F/45F migration where possible;
- keep configuration flash generic SPI NOR;
- keep the core HDL vendor-neutral;
- archive tested toolchain versions in CI/container metadata;
- record exact manufacturer OPNs in the BOM rather than only `ECP5-45`;
- review Lattice PCNs and product notices before each production batch.

The project goal is therefore **Engeler-equivalent behaviour on ECP5**, not a gate-for-gate port of the Spartan-3AN design.
