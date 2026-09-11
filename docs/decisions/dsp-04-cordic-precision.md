# DSP Decision 04 — CORDIC precision

## Status
Resolved — CORDIC is NOT used.

## Context
The Engeler paper mentions CORDIC as a natural FPGA implementation for vector
angle/rotation operations. We evaluated whether to include a CORDIC for:
1. Computing carrier phase: `arg(X_carrier)`
2. Rotating AM/PM bins into the carrier frame for envelope/phase extraction

## Decision
The design avoids CORDIC entirely by using implicit rotation via dot and cross
products:

```
AM_raw = AM · carrier        (dot product → real component)
PM_raw = PM × carrier        (cross product → imaginary component)
```

Where `·` is the dot product (real×real + imag×imag) and `×` is the cross
product (imag×real - real×imag). This rotates the AM and PM Goertzel outputs
into the carrier reference frame without computing any angle.

The trade-off:
- Pro: no CORDIC pipeline stages → lower latency, lower LUT cost
- Pro: no quantization error from angle representation and rotation
- Con: the AM/PM observables are not normalised (they scale with signal
  amplitude); this is acceptable because downstream blocks (am_bit_extractor,
  pm_phase_discriminator) already work with unnormalised soft metrics or
  compensate via the early-minus-late discriminator normalisation

If future work requires an explicit phase display (degrees for instrumentation)
or a phase-locked loop with angle-domain control, a CORDIC can be added as a
diagnostic output only, not in the main signal path.

## Implementation
The dot/cross product pipeline (`engeler_observables.sv`) uses:
- Three parallel `goertzel_complex_12` instances to convert state pairs to
  complex bins (multiply by cos/sin of 30°)
- Three pipeline stages: bins → products → sums
- Three 33×33 multiplies per stage (total 6 multiplies for AM dot + PM cross)
- All multiplies are ordinary signed SystemVerilog `*` operators, left to
  Yosys to map onto MULT18X18D tiles or LUTs

## Resource impact
A CORDIC with 16-bit precision and 16 iterations would cost ~16× (3 adders +
2 muxes) ≈ 768 LUTs and 16 pipeline stages of latency. The implicit rotation
achieves better precision at zero latency cost beyond the three multiply/add
stages already needed.

## References
- `docs/03-goertzel-detector.md` — CORDIC discussion
- `rtl/goertzel/engeler_observables.sv` — implicit rotation implementation
- `rtl/goertzel/goertzel_complex_12.sv` — state-to-complex converter