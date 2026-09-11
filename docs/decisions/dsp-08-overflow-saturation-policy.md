# DSP Decision 08 — Overflow and saturation policy

## Status
Resolved. Every arithmetic block in the detector saturates rather than wraps.
Saturation is to symmetric signed bounds; overflow is flagged persistently until
reset.

## Context
FPGA arithmetic in SystemVerilog wraps by default (two's complement modular
arithmetic). In a signal processing chain, wrapping would:
- invert the sign of large accumulated sums;
- produce near-maximum negative values from near-maximum positive overflow;
- corrupt downstream correlations and lock decisions silently.

The Engeler paper does not specify a saturation policy, but any practical
fixed-point receiver requires one.

## Decision

### Saturation policy
Every accumulator, product truncation, and output shift saturates:
- Positive overflow: clamp to max positive (`0b0_111...111`)
- Negative overflow: clamp to max negative (`0b1_000...000`)
- In-range: truncate to target width

This is symmetric saturation: both bounds are the full signed range of the
target width.

### Overflow signalling
| Signal | Meaning | Persistence |
|---|---|---|
| `goertzel_resonator.overflow` | Saturation occurred in recurrence or scale step | Sticky until reset |
| `engeler_goertzel_bank.overflow` | OR of all three resonator overflow flags | Sticky until reset |
| `engeler_observables.overflow` | Same as bank overflow (passed through) | Sticky until reset |

Overflow is **not** auto-clearing: a single overflow event keeps the flag high
until reset, so a transient saturation during initial acquisition or a brief
interference burst is never silently ignored.

### Blocks with saturation
| Block | Saturation point | Function |
|---|---|---|
| `goertzel_resonator` | Recurrence output, scale output | `saturate()` |
| `pm_chip_integrator` | Chip accumulator after shift | `saturate_output()` |
| `am_bit_extractor` | Evidence after three-window sum | `saturate_output()` |
| `frequency_discipline` | Estimated offset, trim output | `trim_clip()` |
| `second_phase_detector` | N/A (position modulo arithmetic) | Counter wrap is intentional |

### Bounded-division output
`pm_phase_discriminator`'s sequential divider saturates the quotient to
±(2^(PHASE_ERROR_BITS-1) - 1), preventing a divide-by-zero or near-zero
denominator from producing an unbounded result.

### Why saturation beats wrapping
Consider a PM chip integrator that accumulates 120 carrier-cycle observables.
Each is a 67-bit signed value. The sum could reach 67 + log2(120) ≈ 74 bits.
If this wrapped at 32 bits:
- A large positive sum could become a large negative output.
- The downstream PRN correlator would see a sign flip for that chip.
- The correlation peak could be reduced or sign-inverted.
- The lock controller might lose lock on a strong, clean signal.

With saturation:
- The output simply clips at ±(2^31 - 1).
- The chip appears as "strongest possible signal" rather than "inverted signal."
- The correlation still peaks, just with a flatter top.

### What is NOT saturated
- The clock discipline integrator uses conditional integration (anti-windup)
  instead of saturation: when the total trim request would exceed limits, the
  integrator only updates if driving back toward range.
- Second position counters wrap naturally (modulo SECOND_CYCLES).

## Verification
- `formal/goertzel_resonator.sby`: proves saturation bounds are never exceeded
- `sim/engeler_goertzel_bank_tb.sv`: checks overflow is not asserted for normal
  stimuli
- `sim/pm_chip_integrator_tb.sv`: verifies saturation at output

## References
- `rtl/goertzel/goertzel_resonator.sv` — saturate() function
- `rtl/pm/pm_chip_integrator.sv` — saturate_output() function
- `rtl/am/am_bit_extractor.sv` — saturate_output() function
- `rtl/clock_discipline/frequency_discipline.sv` — trim_clip(), anti-windup
- `rtl/pm/pm_phase_discriminator.sv` — divider quotient saturation