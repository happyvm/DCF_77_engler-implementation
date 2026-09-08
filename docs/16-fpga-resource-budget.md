# FPGA resource budget: do not exceed the original receiver class

## Policy

The ECP5 device may physically contain more resources than the historical FPGA, but the **release receiver design must fit inside a resource envelope equivalent to the original Xilinx XC3S1400AN**.

This prevents the reconstruction from hiding algorithmic inefficiency behind a much larger modern FPGA.

The ECP5-45F remains useful as a development/availability target because it provides routing and debug margin, but unused silicon is not permission to enlarge the actual receiver architecture.

## Historical XC3S1400AN resource envelope

AMD/Xilinx documents the XC3S1400AN with:

```text
Equivalent logic cells       25,344
Slices                        11,264
CLB flip-flops                22,528
Distributed RAM               176 Kibit
Block RAM                     576 Kibit
Dedicated 18x18 multipliers   32
DCMs                           8
```

A Spartan-3A/3AN slice contains two 4-input LUTs and two storage elements, so the useful direct ECP5 comparison is approximately:

```text
LUT4-equivalent budget        22,528
flip-flop budget              22,528
```

The BRAM mapping is especially convenient: ECP5 EBRs are 18 Kibit, therefore:

```text
576 Kibit / 18 Kibit = 32 EBR blocks
```

## Hard release limits

The initial synthesis budget is therefore:

| Resource | Release limit |
|---|---:|
| LUT4 equivalents | 22,528 |
| flip-flops | 22,528 |
| distributed/LUT RAM | 176 Kibit soft sub-limit |
| EBR18 blocks | 32 |
| total EBR capacity | 576 Kibit |
| 18x18 multipliers/DSPs | 32 |
| clock managers | no more than historical need; ECP5 physical limit is already lower |

These are **maximums**, not targets. Lower use is preferred.

## What counts against the budget

The release budget includes everything required for the receiver to operate as a standalone Engeler-equivalent unit:

- ADC interface and buffering;
- carrier/phase detector;
- AM processing;
- PM/PRN correlator;
- second/minute synchronization;
- 3600-second history;
- ML decoder;
- clock-discipline logic;
- AGC control;
- normal display/control interfaces required by the final receiver.

## Development-only instrumentation

Large logic analyzers, oversized raw-sample FIFOs, temporary debug cores, experimental parallel detectors and host-only diagnostics may exceed the historical budget **only in a separate development build profile**.

They must not be required to obtain the claimed receiver performance.

Two synthesis profiles should therefore exist:

```text
release_reference
    must satisfy XC3S1400AN-equivalent limits

lab_debug
    may use spare ECP5 resources for instrumentation
```

Any algorithm that works only in `lab_debug` because it consumes more than the historical resource envelope is not accepted as the main implementation.

## Why keep the 45F then?

The 45F is still useful because:

- it is easier to route while the design is moving;
- it gives room for temporary test instrumentation;
- it avoids prematurely choosing a smaller density before synthesis data exists;
- it gives sourcing flexibility;
- the same PCB may later accept a lower density where pin migration permits.

But CI/release checks make the extra silicon logically invisible to the production receiver.

## Relationship to ECP5-25F

The ECP5-25F is close to the historical logic scale but is not a perfect resource clone. In particular it has fewer 18x18 multipliers than the XC3S1400AN while having more embedded RAM than the historical block-RAM budget.

Therefore we should **not** use “fits in 25F” as the definition of historical equivalence.

Historical equivalence is defined by the explicit resource limits above.

If the final design also fits comfortably in a 25F, that becomes a useful cost/lifecycle option.

## CI enforcement

The machine-readable limits are stored in:

```text
rtl/resource_budget.json
```

The synthesis pipeline should parse Yosys/nextpnr utilization reports and fail the `release_reference` build if any hard limit is exceeded.

Because vendor resource names differ, the CI adapter must document how it maps:

- ECP5 `LUT4` -> LUT4-equivalent count;
- ECP5 flip-flops -> FF count;
- ECP5 `DP16KD` -> 18-Kibit EBR count;
- ECP5 `MULT18X18D` -> 18x18 multiplier count.

The source JSON should remain vendor-neutral enough to support a future FPGA migration.

## Memory discipline

The 576-Kibit BRAM cap means raw ADC recordings cannot live in FPGA memory for long periods. That is consistent with the original architecture.

Use EBR for compact state:

- FIFOs;
- detector states;
- soft-bit/history memory;
- correlation accumulators;
- small debug snapshots.

Stream large captures off-board.

## Optimization rule

Do not optimize merely to minimize utilization before correctness is established, but never design an algorithm whose final architecture inherently requires more resources than the XC3S1400AN envelope.

The intended workflow is:

1. implement clearly;
2. verify bit-accurate behaviour;
3. synthesize;
4. if a historical limit is exceeded, restructure/time-share/pipeline intelligently;
5. keep performance measurements after the optimization;
6. only then declare the block complete.

The objective is **Engeler-class performance within Engeler-class FPGA resources**, implemented on maintainable modern silicon.
