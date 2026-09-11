# DSP Decision 02 — Goertzel scaling

## Status
Resolved. The three scaling constants for the Engeler Goertzel bank are derived
from the paper's bandwidth relationship `B_3dB ~= 0.32 * (1 - k) * Fc` and are
coded as Q1.17 fixed-point defaults.

## Context
Engeler uses three Goertzel resonators fed from the same ADC stream, each with a
different state-scaling factor `k` applied once per carrier cycle. The effective
3 dB bandwidth is:

```
B_3dB ≈ 0.32 × (1 - k) × 77.5 kHz
```

Different observables need different selectivity:
- Carrier reference: narrow, adaptively tightened by the clock loop
- AM: ~15 Hz (envelope changes slowly)
- PM: ~930 Hz (must track the 512-chip phase modulation)

## Decision

| Path | Scale k (Q1.17) | Decimal k | B_3dB estimate | Rationale |
|---|---|---|---|---|
| Carrier | 131059 | 0.999908 | ~2.3 Hz | Narrow initial value; future clock loop will tighten |
| AM | 130993 | 0.999404 | ~15 Hz | Wide enough for the 100/200 ms amplitude notch |
| PM | 126157 | 0.962502 | ~930 Hz | Must pass the ~3.875 kHz chip rate (~120 cycles/chip) |

The resonator coefficient (2×cos(2π/12) = √3 for 12 samples/cycle) is:
- `RESONATOR_COEFF = 227023` (Q2.17: 1.732047... vs true √3 = 1.732050...)

## Implementation
All three constants are `localparam` in `engeler_goertzel_bank`, overridable at
instantiation. `engeler_detector` and `dcf77_receiver_core` carry matching
overridable defaults so a time-compressed simulation can widen the bins in
proportion to a shortened second without touching the bank's own defaults.

## Verification
- `sim/engeler_goertzel_bank_tb.sv`: injects four cycles of a 12-phase carrier,
  checks state vectors against reference integers, verifies `cycle_valid` pulses,
  and rejects unexpected saturation.
- `formal/goertzel_resonator.sby`: bounded proof of saturation and recurrence
  correctness with zero sample_ce hold.

## References
- `docs/03-goertzel-detector.md` — Engeler's bandwidth derivation
- `docs/31-goertzel-rtl.md` — RTL implementation details
- `rtl/goertzel/engeler_goertzel_bank.sv` — CARRIER_SCALE, AM_SCALE, PM_SCALE
- `rtl/goertzel/goertzel_resonator.sv` — RESONATOR_COEFF, SCALE_COEFF