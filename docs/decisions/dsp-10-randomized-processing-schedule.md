# DSP Decision 10 — Randomized processing schedule

## Status
Resolved — NOT currently implemented. Deferred to a future receiver revision.

## Context
Engeler's paper describes a randomised processing schedule as a technique to
spread digital processing energy across the carrier cycle, reducing the
amplitude of periodic self-interference at 77.5 kHz and its harmonics. The idea
is:
- Instead of performing all Goertzel operations, envelope detection, and
  correlation on a fixed schedule aligned to the carrier cycle;
- Randomise (or pseudo-randomise) which operations execute on which sample
  clock, while maintaining the same throughput;
- This spreads the digital switching noise spectrum, reducing narrowband
  interference at the exact carrier frequency.

## Decision
The current RTL does NOT implement randomised processing. All operations are
clock-aligned:
- Goertzel recurrence: every `sample_ce` (930 kHz, 12 per carrier cycle)
- Cycle scaling: every 12th sample (77.5 kHz)
- Envelope/observable computation: one cycle after scale (77.5 kHz pipeline)
- AM detection: once per second
- PM correlation: once per second
- ML decode: once per minute

## Rationale
Randomised processing was deferred for Rev.0 because:
1. **Complexity**: randomising execution order without affecting the
   deterministic Goertzel recurrence (which depends on exact sample timing)
   would require significant redesign.
2. **Verification burden**: randomised behaviour is harder to test and formally
   verify.
3. **Unknown need**: self-interference from the FPGA to the 77.5 kHz antenna is
   a measurement question (see `docs/09-gaps-and-open-questions.md` §Measurement
   questions). Without hardware measurements of the actual interference level,
   we don't know if randomisation is needed at all.
4. **ECP5 capability**: the ECP5 has spread-spectrum PLL options and per-bank
   slew rate control that may address self-interference at the physical level
   without RTL changes.

## Mitigations in current design
- The sample rate (930 kHz) is precisely 12× the carrier, putting the strongest
  digital harmonics at multiples of 930 kHz, not at 77.5 kHz.
- The ADC interface uses a dedicated serial clock (adc_if.sv) separate from the
  main system clock, reducing coupling.
- The PCB layout can physically separate the FPGA from the antenna input path
  (HAT+ form factor provides ~40mm of separation).

## Future implementation path
If hardware measurements show problematic self-interference:
1. The Goertzel recurrence must remain deterministic (fixed sample timing).
2. Downstream processing (observable computation, envelope detection,
   correlation) can be dithered by ±1-2 cycles using an LFSR.
3. The LFSR state can be deterministic (reset to a known seed) so verification
   is reproducible.
4. The randomised schedule would be a configurable option (`RANDOMIZE_EN`).

## References
- `docs/05-clock-sync-noise.md` — self-interference analysis
- `docs/09-gaps-and-open-questions.md` — measurement questions §4
- `rtl/goertzel/goertzel_resonator.sv` — deterministic recurrence
- `rtl/core/engeler_detector.sv` — pipeline alignment