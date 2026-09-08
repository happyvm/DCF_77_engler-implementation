# Reconstruction plan

The safest path is to rebuild the receiver as a sequence of independently testable layers.

## Phase 0 — software/reference model

Before hardware, create a DCF77 signal generator that can emit:

- 77.5 kHz carrier;
- AM0/AM1 envelopes;
- PM0/PM1 pseudo-random phase modulation;
- correct 60-second time frames;
- adjustable AWGN, narrowband interferers and impulsive noise;
- local sampling-clock error in ppm.

Use this model to validate all FPGA arithmetic and ML decoding offline.

**Exit criterion:** software detector reproduces the expected bit and synchronisation behaviour over a sweep of SNR and clock error.

## Phase 1 — analog front-end only

Build antenna + input buffer + band-pass + PGA. Do not start with the full FPGA algorithm.

Measure:

- antenna resonance and Q;
- pass-band centre/width and group delay;
- total gain range;
- input-referred/equivalent noise;
- overload behaviour near strong local interferers.

**Exit criterion:** a 77.5 kHz carrier can be seen reliably at the ADC input with adequate headroom and no oscillation/self-coupling.

## Phase 2 — raw ADC capture

Clock the ADC at **930 kS/s** and capture long raw blocks through the Raspberry Pi host interface. Add only enough FPGA logic for acquisition and transport.

Use captured data to develop the detector in Python/C first. This makes analog and algorithmic debugging independent.

**Exit criterion:** repeatable raw recordings contain the expected DCF77 AM envelope and, at a sufficiently clean location, measurable carrier phase structure.

## Phase 3 — AM detector and second edge

Implement:

- carrier-centred filtering/Goertzel;
- AM Goertzel path;
- envelope extraction;
- simple threshold AM decoder;
- then AM-template correlation for robust second sync.

**Exit criterion:** stable 1 bit/s AM output and second boundary under ordinary indoor noise.

## Phase 4 — carrier phase and PM detector

Add:

- narrow carrier-reference Goertzel;
- CORDIC/vector rotation;
- PM Goertzel path around 930 Hz effective bandwidth;
- PM0/PM1 correlation using the official 512-chip pattern;
- PM soft-bit output.

**Exit criterion:** PM correlation peak tracks the AM-derived second boundary and resolves bit polarity on clean data.

## Phase 5 — minute synchronisation

Implement the high-immunity minute-start correlation using the known PM frame pattern. Use AM synchronisation as the coarse seed for the PM search to reduce memory/compute cost.

**Exit criterion:** stable current-second/minute-boundary estimate without relying on the conventional missing-AM-pulse detector alone.

## Phase 6 — ML time decoder

Add a 3600-second circular history and hierarchical correlation:

1. current second;
2. minute 0-59;
3. hour 0-23.

Use soft bits. Add explicit confidence gating so random/noise input cannot force a displayed time.

**Exit criterion:** clean-signal acquisition <=60 s and graceful extension of acquisition time as SNR falls.

## Phase 7 — clock discipline

Add phase comparison, burst-noise hole punching and fractional digital correction. Narrow the carrier loop bandwidth as the correction converges.

**Exit criterion:** measured processing-clock error <=0.1 ppm while locked and no loss of receiver stability during normal day/night signal variation.

## Phase 8 — EMI/self-leakage hardening

Measure the antenna spectrum with the complete HAT running on a Raspberry Pi. If digital spurs appear at 77.5 kHz or related aliases:

- add random-length processing bursts as in the paper;
- improve supply isolation and grounding;
- move/shield high-speed digital circuitry;
- A/B test Raspberry Pi CPU/Ethernet/Wi-Fi activity;
- disable LCD backlight and nonessential host traffic;
- characterize the local 1.1 V core buck separately.

**Exit criterion:** enabling the full FPGA and Raspberry Pi host workload does not measurably degrade carrier SNR beyond the accepted HAT budget.

## Phase 9 — absolute timing calibration

Compare the decoded second edge to GPS/PPS or a lab timebase. Characterise:

- ferrite-antenna group delay;
- analog-filter delay;
- ADC/FPGA pipeline delay;
- PPS output-path delay;
- location-dependent propagation delay.

**Exit criterion:** repeatable offset and jitter consistent with the target accuracy chosen for the rebuild.

## Repository structure recommended for implementation

```text
rtl/
  adc/
  goertzel/
  cordic/
  am/
  pm/
  sync/
  clock_discipline/
  ml_decoder/
  agc/
  debug/

sim/
  signal_generator/
  vectors/
  cocotb_or_equivalent/

hardware/tscircuit/
  pin-plan.json
  power-plan.json
  src/
  dist/

software/
  capture/
  analysis/
  decoder_reference/
```

Keep the software model as the golden reference for every RTL block. This is particularly important because the paper does not provide the original FPGA source.
