# DSP Decision 07 — ML confidence thresholds

## Status
Resolved. Each ML search engine applies two qualification gates: an absolute
minimum score and a minimum gap between the best and second-best candidate.
These are calibration constants; they will be re-validated against real DCF77
signal captures.

## Context
The Engeler paper advocates soft-decision ML decoding rather than hard 0/1
thresholding. The decoder evaluates all legal candidates against the received
soft evidence and selects the one with the highest score. However, a candidate's
score must also:
- be objectively high enough (not just "least bad of 60 noise values");
- be unambiguously better than the runner-up (not a near-tie).

These gates are what turn a "winning candidate" into a "qualified lock."

## Decision

### Minute-value search (bits 21-28, 8 evidence values)
```
MINUTE_MIN_SCORE = (EVIDENCE_BITS > 2) ? (1 << (EVIDENCE_BITS - 2)) : 1
                 = 2^14 = 16384   [with EVIDENCE_BITS = 16]
MINUTE_MIN_GAP   = MINUTE_MIN_SCORE >> 2 = 4096
```

An 8-bit candidate where every evidence agrees could reach 8 × 2^15 = 262144.
Requiring 1/16 of that (16384) still rejects a noise candidate while staying
reachable by a real signal nowhere near full-scale confidence.

The gap of 4096 means the runner-up must trail by more than one marginal
bit's worth of separation (a single flipped bit swings the score by 2 × that
bit's evidence, potentially up to 131072).

### Hour-value search (bits 29-35, 7 evidence values)
```
HOUR_MIN_SCORE = (EVIDENCE_BITS > 1) ? ((7 × (1 << (EVIDENCE_BITS - 1))) >> 4) : 1
               = 7 × 32768 >> 4 = 14336   [with EVIDENCE_BITS = 16]
HOUR_MIN_GAP   = HOUR_MIN_SCORE >> 2 = 3584
```

Same derivation as the minute floor, scaled from 8 to 7 evidence bits.

### Minute-boundary sync (pm_minute_sync, 15-second matched filter)
```
MIN_SCORE      = 8 × PM_MIN_PROMPT_MAGNITUDE
               = 8 × ((1 << (SOFT_BITS - 4)) / 120 × CYCLES_PER_CHIP)
MIN_GAP        = MIN_SCORE >> 2
MARKER_MIN_MEANS = 11
```

Three independent qualification gates:
1. Absolute floor: `best ≥ MIN_SCORE` (8× the single-second floor)
2. Gap: `best - second ≥ MIN_GAP`
3. Relative dominance: `60 × best ≥ 11 × Σ|correlation|` over 60 samples

The relative test is critical: when the real minute marker is absent (dropout),
the 15-second filter will still find a maximum among the ~45 data second windows,
but that maximum is only ~8-10× the mean |correlation|, not the ~15× a true
aligned marker would achieve.

### Detector-level PM floor
```
PM_MIN_PROMPT_MAGNITUDE = (1 << (SOFT_BITS - 4)) / 120 × CYCLES_PER_CHIP
```

A chip-level soft value saturates at ±2^(SOFT_BITS-1). The floor is set so that
a carrier reaching just 1/16 of a chip's full range, integrated coherently over
512 chips, still clears it. This is well above the √512-scaled random walk of
equivalent-amplitude noise.

## Qualification gating chain
```
pm_minute_sync:  best ≥ MIN_SCORE && gap ≥ MIN_GAP && marker_dominant
    → minute_locked (to detector and lock controller)
    
ml_field_sequencer: minute_confident && hour_confident
    → ml_frame_valid (to ml_decoder_controller)
    
ml_decoder_controller: CONSISTENT_FRAMES consecutive consistent frames
    → publish_valid (to lock controller)
    
receiver_lock_controller: ml_qualified && minute_qualified && frequency_qualified
    → time_valid (to user outputs)
```

## Calibration note
All thresholds are calibration constants, not measured ones. They must be
re-validated once the real receiver noise floor and DCF77 signal SNR are
characterised on hardware.

## References
- `rtl/ml_decoder/ml_field_sequencer.sv` — MINUTE_MIN_SCORE, HOUR_MIN_SCORE
- `rtl/ml_decoder/minute_candidate_search.sv` — MIN_SCORE, MIN_GAP
- `rtl/ml_decoder/hour_candidate_search.sv` — MIN_SCORE, MIN_GAP
- `rtl/sync/pm_minute_sync.sv` — MIN_SCORE, MIN_GAP, MARKER_MIN_MEANS
- `rtl/core/engeler_detector.sv` — PM_MIN_PROMPT_MAGNITUDE, MINUTE_MIN_SCORE
- `rtl/control/receiver_lock_controller.sv` — ACQUIRE_RESULTS, EXIT_FAILURES
- `rtl/ml_decoder/ml_decoder_controller.sv` — CONSISTENT_FRAMES