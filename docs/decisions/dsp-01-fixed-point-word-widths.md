# DSP Decision 01 — Fixed-point word widths

## Status
Resolved. The word widths are set by Verilog parameters with defaults derived from
Engeler's paper and the signal chain budget. They are frozen for Rev.0 synthesis
but remain overridable at instantiation for simulation/characterisation.

## Context
Engeler's paper describes a 12-bit ADC with internal fixed-point arithmetic but
does not publish exact HDL widths. We must choose widths that:
- preserve the ADC's 14-bit dynamic range (LTC1407A-1);
- accumulate 12-120 carrier cycles per chip without overflow;
- survive the Goertzel recursion with bounded, saturated state;
- stay within the XC3S1400AN resource envelope.

## Decision

| Signal path | Format | Rationale |
|---|---|---|
| ADC sample in | 14-bit signed | LTC1407A-1 native width |
| Goertzel state | 32-bit signed | 14-bit input + 18 guard bits for the recursive pole near 1 |
| Goertzel coefficient | Q1.17 (19-bit signed) | cos(pi/6) fits in 1 integer bit; 17 fractional bits keep the pole accurate |
| Goertzel product | 51-bit (32+19) | full product before truncation |
| AM/PM observable | 67-bit signed (2×STATE+3) | dot/cross product of 33-bit complex values + 3 pipeline stages |
| AM soft bit | 32-bit signed | AM window sum (7 750 cycles) shifted right by 20 |
| PM chip soft | 32-bit signed | 120-cycle sum shifted right by 24 |
| PM correlation | 42-bit signed (32+10) | 512 chips with 10 guard bits against overflow at full excursion |
| Phase error | Q8.16 (24-bit signed) | 8 integer bits (±128 cycles) with 1/65536 cycle resolution |
| Trim increment | 24-bit signed | sample_scheduler accumulator LSBs (±~4 ppm range) |
| ML evidence | 16-bit signed | truncated from AM/PM soft: the ML decoders need at most 60 values summed, so 16+6 bits score wide |
| ML score | 20-bit signed | 8 bits × 16-bit evidence + 4 guard bits |

## Verification
- Goertzel state width: `formal/goertzel_resonator.sby`
- Accumulator widths: `formal/pm_chip_integrator.sby`, `formal/pm_prn_correlator.sby`
- Overflow tracking: all modules expose persistent `overflow` flags
- Resource budget: `make resource-check`

## References
- `docs/03-goertzel-detector.md` — Engeler's fixed-point guidance
- `rtl/goertzel/goertzel_resonator.sv` — default SAMPLE_BITS/STATE_BITS/COEFF_BITS
- `rtl/core/engeler_detector.sv` — SOFT_BITS, AM_OUTPUT_SHIFT, PM_OUTPUT_SHIFT
- `rtl/pm/pm_chip_integrator.sv` — INPUT_BITS, OUTPUT_BITS, OUTPUT_SHIFT
- `rtl/pm/pm_prn_correlator.sv` — SOFT_BITS, ACC_BITS
- `rtl/clock_discipline/frequency_discipline.sv` — PHASE_BITS, PHASE_FRAC_BITS, TRIM_BITS