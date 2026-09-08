# Clock-source selection: precision, availability and frequency

## Status

No oscillator OPN or exact nominal frequency is frozen yet.

The Rev.0 baseline is now a **simple fixed TCXO**. DCF77 carrier discipline remains digital inside the ECP5/sample-time architecture.

A DCTCXO is retained only as an optional experimental path if measurements later show a worthwhile holdover or phase-noise benefit.

The earlier `SiT5348 @ 24.180000 MHz` proposal is retained only as an arithmetic study. It is not a production decision.

## Why fixed TCXO is the default

A digitally controlled TCXO would let DCF77 physically steer the oscillator, but that is not required to reproduce Engeler's receiver behaviour.

With a fixed TCXO:

```text
TCXO
  -> fixed ECP5 PLL
  -> fractional sample scheduler / disciplined timebase
  -> 930 kS/s average sample rate
```

The FPGA can retain the last trusted frequency correction during carrier loss, so useful holdover correction is still available without requiring an I2C-controlled oscillator.

Benefits of the fixed-TCXO baseline:

- simpler clock block;
- no oscillator-control protocol dependency;
- easier substitution across oscillator vendors/families;
- fewer failure modes;
- less RTL/firmware tied to a particular timing vendor;
- closer in spirit to Engeler's digitally corrected local oscillator;
- no need to perturb the physical FPGA clock when tracking DCF77.

## Precision requirement

Engeler reports a disciplined local-clock target around `0.1 ppm`, or about `100 ppb`.

Useful holdover intuition:

| oscillator stability | worst-case drift per second | worst-case drift per day |
|---:|---:|---:|
| ±500 ppb | ±500 ns/s | ±43.2 ms/day |
| ±250 ppb | ±250 ns/s | ±21.6 ms/day |
| ±100 ppb | ±100 ns/s | ±8.64 ms/day |
| ±50 ppb | ±50 ns/s | ±4.32 ms/day |
| ±20 ppb | ±20 ns/s | ±1.728 ms/day |

The synchronized PPS accuracy is not determined by the TCXO alone. Propagation, ferrite phase/group delay, analog-filter group delay, carrier phase estimation, calibration and RF noise eventually dominate.

Current design rule:

```text
baseline target: around ±100 ppb class if real stock/cost permit
better than ±100 ppb: buy only when justified by holdover/error budget
```

## Availability is part of the specification

Do not select a custom oscillator frequency first and then ask whether it can be bought.

Selection order:

1. define synchronized timing and holdover requirement;
2. find exact orderable TCXO OPNs at Digi-Key/Mouser or equivalent authorized distributors;
3. prefer standard catalogue frequencies and meaningful stock depth;
4. check operating temperature and supply/output compatibility;
5. verify ECP5 PLL legality;
6. calculate fractional 930 kS/s scheduling resolution;
7. evaluate EMI relationships to 77.5 kHz;
8. choose the OPN/frequency only after the complete comparison.

Stock numbers are dated observations, not permanent component properties. Re-check immediately before BOM release.

## SiTime remains a preferred vendor, not a mandatory one

SiTime Super-TCXO families are attractive because of stability under temperature/airflow/vibration and broad programmable-frequency offerings.

A manufacturer example such as a 25 MHz SiT5346 configuration can provide around ±0.1 ppm class stability over an extended temperature range, but an example configuration is not automatically an acceptable BOM part.

The actual selected part must also be available at the distributor and in the required voltage/package/temperature configuration.

Other oscillator vendors remain valid if they satisfy the same electrical, lifecycle and sourcing requirements.

## DCTCXO option

Do not delete the possibility of DCTCXO experimentation.

Where practical, a selected family/footprint may expose or reserve the extra control pins needed by a digitally tunable variant, but the reference board must work correctly with a fixed-frequency population.

A DCTCXO becomes justified if measurements show a material advantage in one or more of:

- long carrier-loss holdover;
- PPS phase noise;
- sample-timing jitter;
- startup acquisition;
- temperature transients.

It should not be selected merely because its digital tuning resolution looks impressive on a data sheet.

## Frequency-selection policy

The clock frequency is no longer chosen for exact arithmetic with 77.5 kHz.

The 24.18 MHz study had:

```text
24.18 MHz = 312 * 77.5 kHz
```

This produces beautiful integer ratios but also makes the board clock exactly harmonically related to the extremely weak wanted carrier.

That relationship may increase deterministic self-interference risk.

Therefore standard frequencies such as 10, 20, 24, 25, 26 MHz or other well-stocked catalogue values should be compared on availability and EMI before any custom value is requested.

## Fractional sample scheduling is acceptable

For a fixed TCXO system clock:

```text
f_sample = f_system * INC / 2^N
```

The existing 40-bit implementation already provides much finer numerical correction than the ~3 ppb step reported for Engeler's clock-correction mechanism.

The bounded event-grid timing quantization is acceptable as the current baseline and must be validated by measurement rather than eliminated at the cost of poor component sourcing.

Reference implementation:

```text
rtl/core/sample_scheduler.sv
```

## Holdover behaviour

When DCF77 carrier lock is lost:

1. freeze the last trusted digital frequency-correction estimate;
2. continue from the fixed TCXO;
3. increase a holdover-age/uncertainty metric;
4. keep PPS monotonic;
5. reacquire carrier phase without an abrupt time jump;
6. resume tracking only after confidence checks pass.

This allows a good TCXO plus learned correction to provide substantially better holdover than an uncorrected inexpensive quartz oscillator.

## Decision gate before schematic freeze

Do not place the final oscillator OPN until these values are explicit:

```text
absolute synchronized PPS target
required holdover duration
allowed holdover time error
board operating-temperature range
acceptable supply rail(s)
required logic output standard
minimum distributor/factory stock depth
maximum oscillator BOM cost
acceptable package/footprint
```

Current baseline:

```text
fixed TCXO
standard stocked frequency
LVCMOS
industrial temperature preferred
~±100 ppb class target where availability/cost justify it
DCF77 discipline performed digitally in ECP5
DCTCXO optional for experiments
```
