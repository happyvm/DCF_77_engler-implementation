# DSP Decision 05 — AGC thresholds and time constants

## Status
Resolved — no explicit AGC block exists. Envelope tracking and level
normalisation happen implicitly through the Goertzel bank's own exponential
memory and the second-phase detector's peak-hold reference.

## Context
The DCF77 receiver front-end (LTC1562 filter + LTC6912-1 PGA) sets analog gain.
The LTC6912-1 has digital gain control in 1 dB steps (0 to 63 dB range via SPI).
There is no closed-loop AGC in the current RTL. Instead:

1. The Goertzel bank itself behaves as a first-order exponential average with
   time constant τ = 1 / (B_3dB) set by the scaling factor k.
2. The second-phase detector maintains a peak-hold reference level for AM edge
   detection.

## Decision

### Goertzel time constants
| Path | B_3dB | Time constant (τ) | Settling time (5τ) |
|---|---|---|---|
| Carrier | ~2.3 Hz | ~70 ms | ~350 ms |
| AM | ~15 Hz | ~10.6 ms | ~53 ms |
| PM | ~930 Hz | ~171 µs | ~855 µs |

These are the inherent time constants of the periodic scaling. No additional AGC
time constant is applied.

### AM edge detection reference
`second_phase_detector` maintains a slow peak-hold reference for the AM envelope
magnitude:

| Parameter | Value | Meaning |
|---|---|---|
| REF_DECAY_SHIFT | 15 | Reference decays by 1/32768 per carrier cycle → τ ≈ 0.42 s |
| EDGE_DROP_SHIFT | 5 | Edge detected when envelope falls below ref × (1 - 1/32) |
| Rearm threshold | EDGE_DROP_SHIFT+1 = 6 | Re-arms when envelope climbs above ref × (1 - 1/64) |
| Half-level witness | ref >> 1 | Envelope must actually go below ref/2 to count as a notch |

This is deliberately asymmetric: the reference follows upward (instantly on
exceeding the peak) but decays slowly (τ ≈ 0.42 s), so it remembers the
full-carrier level through the 200 ms amplitude reduction and still follows a
slowly fading carrier.

### PGA gain control
The LTC6912-1 PGA gain is set via SPI (`pga_spi_master.sv`) as an open-loop
configuration value, not a closed-loop AGC. The initial value should be chosen
to place the ADC input near mid-scale in the expected signal environment.

## Future work
A closed-loop AGC may be needed if the receiver operates across widely varying
signal strengths (night vs day, near vs far from Mainflingen). The architecture
would be:
- Monitor the AM bin magnitude or the Goertzel overflow flag
- Adjust the PGA gain via SPI
- Apply a slow time constant (seconds) to avoid modulating the AM data

## References
- `rtl/goertzel/engeler_goertzel_bank.sv` — Goertzel bandwidth constants
- `rtl/sync/second_phase_detector.sv` — REF_DECAY_SHIFT, EDGE_DROP_SHIFT
- `rtl/platform/pga_spi_master.sv` — PGA SPI interface
- `docs/22-ltc6912-pga.md` — PGA selection and configuration