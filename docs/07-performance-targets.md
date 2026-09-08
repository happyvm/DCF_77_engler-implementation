# Performance targets and validation numbers

These values come from the paper's simulations and demonstration-receiver measurements. They are useful as acceptance targets, not as guaranteed performance for a new PCB.

## Detector/decoder comparison

| Receiver configuration | Synchronisation | Decoder | Approx. Eb/N0 limit | Minimum field in paper model | Ground-wave distance estimate |
|---|---|---|---:|---:|---:|
| narrowband diode | AM falling edge | 2-min BCD | 31 dB | 180 µV/m | 1200 km |
| demonstration Goertzel-PM | single-second | 1-h ML | 7.4 dB | 12 µV/m | 2200 km |
| combined CIC/Goertzel AM+PM | full-minute | 1-h ML | 2.7 dB | 7 µV/m | 2400 km |

The distance values assume the paper's antenna/front-end, atmospheric/internal-noise model and ground-wave propagation. Indoor man-made interference can dominate and make geographic distance almost irrelevant.

## Time-decoder robustness

For a 60-minute maximum observation window and decode probability around 0.5:

- repeated conventional BCD decoding: about **BER 0.13**;
- new ML decoder: about **BER 0.34**;
- theoretical/full-correlation limit is only modestly above the ML result.

The demonstration implementation also includes confidence checks to reduce wrong-time outputs; this intentionally reduces the raw BER limit slightly versus an unconstrained maximum-correlation decoder.

## Clock stability

Target the disciplined local clock to **0.1 ppm or better**. The paper's correction mechanism has about **0.003 ppm adjustment resolution**.

A 0.1 ppm free-running error corresponds to roughly **9 ms/day** accumulated time error. The demonstration receiver therefore updates/synchronises continuously rather than only once per day.

## Timing accuracy

- architecture/design goal: about **1 ms** absolute receiver accuracy before detailed calibration;
- 54 power-up-to-first-sync comparisons against GPS fell within **362 µs** spread in the reported test;
- PM correlation itself can, in principle, localise the second to about **13 µs** (one carrier cycle), but antenna group delay, propagation, filter delay and discrete processing all contribute to absolute-time error.

## Antenna/filter timing errors

A tuned ferrite antenna may be around ±200 Hz off nominal resonance from production spread. The paper estimates roughly **100 µs** group-delay variation from this effect. Absolute timing therefore needs either:

- per-unit calibration;
- a temperature/aging model;
- or a non-resonant wideband antenna architecture.

## Indoor observation reported by Engeler

In one office environment with computers, lab equipment and fluorescent lighting, ordinary low-cost receivers and a simple diode detector only worked close to a window (about 0.5 m), while the demonstration receiver synchronised around 7 m from the window. This is an anecdotal environment-specific test, but it is a useful qualitative target for the final reconstruction.

## Suggested repository test metrics

For each hardware/RTL revision, record at least:

- ADC RMS noise with antenna input terminated/substituted;
- carrier-bin SNR and nearby spur map;
- AGC gain and clipping percentage;
- carrier frequency/phase lock error in ppm;
- second-correlation peak height and peak ratio;
- PM and AM soft-bit distributions;
- raw BER after successful decode;
- ML best/second-best score margins;
- acquisition time from cold start;
- absolute second-edge offset against GPS or a lab reference.
