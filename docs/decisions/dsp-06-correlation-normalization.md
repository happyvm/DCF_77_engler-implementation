# DSP Decision 06 — Correlation normalisation

## Status
Resolved. Each stage in the correlation pipeline applies its own output scaling
via right-shift with saturation. The scheme preserves soft information through
the entire chain without overflow, and the final ML decoder operates on
unnormalised evidence scores.

## Context
The signal chain produces increasingly wide accumulated sums:
1. Goertzel observables: 67-bit dot/cross products
2. AM bit extraction: sum over 7 750 carrier cycles → 80+ bits
3. PM chip integration: sum over 120 carrier cycles → 74+ bits
4. PM correlation: sum over 512 chips → 42 bits
5. ML scoring: sum over 7-8 evidence values → 20 bits

Without normalisation, each stage's output would grow beyond what downstream
blocks can handle.

## Decision

### Output shift schedule
| Stage | Input width | Output width | Right-shift | Loss |
|---|---|---|---|---|
| AM bit extractor | 67-bit observable + log2(7750) guard | 32-bit signed | 20 bits | ~LSB 2^-20 of full scale |
| PM chip integrator | 67-bit observable + log2(120) guard | 32-bit signed | 24 bits | ~LSB 2^-24 of full scale |
| ML AM evidence | 32-bit AM soft | 16-bit signed | Truncation of top 16 bits | ~LSB of full range |
| ML PM evidence | 42-bit PM correlation | 16-bit signed | Truncation of top 16 bits | ~LSB of full range |

### Saturating scale
Every output shift is followed by explicit saturation to the output range:
- Positive overflow → +MAX
- Negative overflow → -MIN
- In-range → truncated value

This is implemented via explicit `saturate_output()` functions in
`am_bit_extractor.sv` and `pm_chip_integrator.sv`.

### PM phase discriminator normalisation
The early-minus-late discriminator normalises by the prompt magnitude:
```
phase_error = OFFSET_CYCLES × (late - early) / (2 × |prompt| + 1)
```
This makes the discriminator response independent of signal strength. The
division uses a sequential restoring divider (one bit per clock, ~PROD_BITS
clocks total).

### PM integration vs noise floor
The PM prompt correlation floor (`PM_MIN_PROMPT_MAGNITUDE`) is set relative to
the chip-level soft value saturation:
```
PM_MIN_PROMPT_MAGNITUDE = (1 << (SOFT_BITS - 4)) / 120 × CYCLES_PER_CHIP
```
This represents ~1/16 of a full-scale chip value, which is well above the
√512-scaled random walk that equivalent-amplitude uncorrelated noise would
produce.

### PM minute sync normalisation
`pm_minute_sync` uses a relative threshold: the 15-second matched filter's best
score must be ≥ MARKER_MIN_MEANS × (mean absolute correlation) over the search
window, scaled as `60 × best ≥ 11 × Σ|correlation|`. This rejects false locks
when the marker is present but weak relative to data-second correlations.

## Verification
- `sim/am_bit_extractor_tb.sv`: exact evidence of -60 (AM0) and +60 (AM1) for
  two-second test
- `sim/pm_prn_correlator_tb.sv`: +51200 for aligned sequence, -51200 for
  inverted
- `formal/pm_prn_correlator.sby`, `formal/pm_chip_integrator.sby`: bounded
  proofs of no overflow in accumulators

## References
- `rtl/am/am_bit_extractor.sv` — OUTPUT_SHIFT, saturate_output
- `rtl/pm/pm_chip_integrator.sv` — OUTPUT_SHIFT, saturate_output
- `rtl/pm/pm_phase_discriminator.sv` — sequential restoring divider
- `rtl/pm/pm_prn_correlator.sv` — ACC_BITS = SOFT_BITS + 10
- `rtl/sync/pm_minute_sync.sv` — MARKER_MIN_MEANS
- `rtl/core/engeler_detector.sv` — AM_OUTPUT_SHIFT, PM_OUTPUT_SHIFT,
  PM_MIN_PROMPT_MAGNITUDE