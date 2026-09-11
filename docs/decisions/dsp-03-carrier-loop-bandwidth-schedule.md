# DSP Decision 03 — Carrier-loop bandwidth schedule

## Status
Resolved. The frequency discipline loop uses two gain sets (acquisition and
tracking) with a PI-like actuator. Default gains are engineering estimates;
re-validation on real hardware is documented as a calibration task.

## Context
The receiver must discipline its sample scheduler from both AM (coarse, once per
second) and PM (fine, sub-cycle early/late discriminator) measurements. The loop
must:
- pull in quickly from up to ±4 ppm initial offset (acquisition);
- maintain quiet tracking once locked (<1 µs jitter target);
- survive measurement dropouts via holdover without windup.

## Decision

### Loop structure
The frequency discipline is a frequency estimator followed by a PI actuator:

```
raw_freq_est = (Δphase × PHASE_TO_TRIM) >> PHASE_FRAC_BITS
freq_est     = freq_est + (raw_freq_est - freq_est) >> estimator_shift
trim_request = freq_est + (phase_error × Kp >> PHASE_FRAC_BITS) + integrator
integrator   += phase_error × Ki >> PHASE_FRAC_BITS
```

### Gain parameters
| Parameter | Acquisition | Tracking | Unit |
|---|---|---|---|
| Estimator shift | ACQ_EST_SHIFT = 1 | TRACK_EST_SHIFT = 4 | bits |
| Proportional Kp | ACQ_KP = 1024 | TRACK_KP = 128 | trim-LSB/cycle |
| Integral Ki | ACQ_KI = 128 | TRACK_KI = 8 | trim-LSB/cycle² |
| Quality minimum | ACQ_QUALITY_MIN = 32 | TRACK_QUALITY_MIN = 64 | (arbitrary 0-255) |
| Lock count | LOCK_COUNT = 8 | — | consecutive points |

### Limits
| Parameter | Value | Rationale |
|---|---|---|
| MAX_TRIM | 32768 (~4 ppm) | ±4 ppm covers all practical TCXO offsets |
| MAX_TRIM_STEP | 2048 | Slew limit: 0.25 ppm per measurement, bumpless holdover recovery |
| OUTLIER_LIMIT | 2^(PHASE_FRAC-1) = 0.5 cycle | Phase excursions outside ±0.5 cycle are rejected |
| DELTA_LIMIT | 2^(PHASE_FRAC-2) = 0.25 cycle | Frequency spikes >0.25 cycle/interval are rejected |
| HOLDOVER_AGE | 4 | 4 consecutive missed measurements → lose lock |

### Anti-windup
Conditional integration: when the requested trim saturates, the integrator only
updates if the update drives back toward the valid range.

### Scaling
- `PHASE_TO_TRIM = 8192`: converts 1 cycle of phase change per measurement
  interval to sample_scheduler accumulator-increment LSBs.
- One trim_inc LSB ≈ 0.000122 ppm at default frequencies.
- ~8,180 trim counts ≈ 1 ppm.

## Verification
- `sim/frequency_discipline_tb.sv`: step response, holdover, lock sequencing
- `formal/frequency_discipline.sby`: bounded proof of saturating arithmetic and
  anti-windup behaviour

## Calibration note
All gains are calibration constants derived from the paper's guidance, not from
measured DCF77 channel characteristics. They must be re-validated once:
- the real TCXO (SiT5356) frequency stability is characterised;
- the DCF77 signal's Allan deviation at 1-1000 s is measured.

## References
- `docs/05-clock-sync-noise.md` — clock discipline noise analysis
- `rtl/clock_discipline/frequency_discipline.sv` — full implementation
- `rtl/core/sample_scheduler.sv` — trim interface