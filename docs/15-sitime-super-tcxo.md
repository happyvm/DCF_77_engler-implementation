# SiTime Super-TCXO clock plan

## Decision

The preferred clock source for the ECP5 rebuild is a **SiTime SiT5348 Super-TCXO in DCTCXO mode**, factory programmed to:

```text
24.180000 MHz
3.3 V
LVCMOS output
±0.05 ppm stability class
DCTCXO / I2C frequency control
±6.25 ppm pull range initially preferred
industrial or extended-industrial temperature grade
```

The exact orderable OPN must be generated/validated with SiTime's part-number configurator before BOM release. Do not infer an OPN by hand in the production BOM.

The SiT5348 is currently a production device and supports arbitrary frequencies from 1 to 60 MHz, digital frequency tuning over I2C, and pull resolution down to approximately 5 ppt in the small pull-range modes.

## Why 24.180000 MHz instead of 25 MHz

24.18 MHz has exact integer relationships to DCF77:

```text
DCF77 carrier       77.5 kHz
ADC target          930 kS/s = 12 * 77.5 kHz
TCXO                24.18 MHz = 26 * 930 kHz
                                = 312 * 77.5 kHz
```

With the ECP5 PLL operated at x5:

```text
24.18 MHz * 5 = 120.90 MHz
```

and therefore:

```text
120.90 MHz / 130 = 930.000 kHz exactly
120.90 MHz / 1560 = 77.500 kHz exactly
```

This eliminates the normal need for the fractional sample scheduler and its 8 ns event-grid quantisation.

## New preferred clock architecture

```text
SiT5348 DCTCXO @ 24.180000 MHz
             |
             +------------------------------+
             |                              |
             v                              v
      ECP5 clock input                 I2C control
             |                              ^
             v                              |
      fixed ECP5 PLL x5                     |
             |                              |
             v                              |
         120.900 MHz                        |
             |                              |
             +--> /130 --> ADC sample_ce    |
             |            930 kS/s          |
             |                              |
             +--> DSP / timing              |
                                            |
DCF77 carrier phase --> slow discipline ----+
```

The DCF77 loop now changes the **physical reference oscillator frequency** through the SiT5348 digital control word. Because both the ECP5 system clock and ADC conversion timing come from the same oscillator, all integer DCF77 relationships remain intact while the oscillator is being disciplined.

## Why DCTCXO instead of a fixed TCXO

A fixed ±50 ppb Super-TCXO is already exceptionally good, but DCTCXO mode gives the receiver a clean hardware actuator for carrier discipline.

Advantages:

- no FPGA PLL reconfiguration;
- no fractional ADC event scheduler in normal operation;
- no per-sample timing dithering;
- physical system clock follows the DCF77 carrier estimate;
- extremely fine frequency-control resolution;
- excellent holdover from the TCXO itself;
- easy software/RTL loop control over I2C.

The old fractional scheduler remains useful as a fallback/test architecture and for boards populated with a generic fixed oscillator.

## SiT5348 capability relevant to this receiver

Manufacturer documentation currently specifies:

- frequency range: 1 to 60 MHz;
- frequency stability option: ±50 ppb;
- 2.5/2.8/3.0/3.3 V supply options;
- LVCMOS or clipped-sine outputs;
- 5.0 x 3.2 mm ceramic 10-pin package;
- DCTCXO digital frequency control over I2C;
- programmable pull ranges from ±6.25 ppm to very large ranges;
- frequency-control resolution down to about 5 ppt for the small pull ranges;
- strong dynamic-temperature behaviour;
- very low acceleration sensitivity options.

For this board the initial preference is **LVCMOS**, because it interfaces directly to the ECP5 clock input without a sine-to-logic conversion stage.

## Pull range

The smallest standard DCTCXO pull range, ±6.25 ppm, is already enormous relative to the ±0.05 ppm TCXO stability class and the ~0.1 ppm disciplined-clock target from Engeler.

Use ±6.25 ppm unless hardware testing reveals a reason to need wider tuning.

A small pull range is attractive because it keeps the finest digital tuning resolution.

The DCF77 loop should never need to use most of this range during normal operation. Large corrections indicate an implementation, measurement, or clock-source problem and should be exposed as a diagnostic.

## Frequency update dynamics

The SiT5348 DCTCXO documentation gives frequency-control timing on the order of:

```text
frequency-change delay    typ ~103 us, max ~140 us
settling time             typ ~16.5 us, max ~20 us
```

This is negligible for a DCF77 frequency-control loop updated once per second or more slowly.

Therefore the loop can safely:

1. estimate carrier phase/frequency error;
2. compute a new DCTCXO offset;
3. write the I2C frequency-control word;
4. wait for the next slow observation interval.

Do not update the oscillator at audio/high rates; the radio source itself only justifies a very slow discipline loop.

## I2C interface

In DCTCXO mode, reserve the SiT5348 control pins in the FPGA interface:

```text
TCXO_SCL
TCXO_SDA
TCXO_A0       if address-select mode is used
TCXO_OE       if the selected ordering option exposes OE
```

Provide pull-ups to the selected digital rail according to the final datasheet configuration.

The clock-control block must support:

- initial device presence/readback checks where supported;
- writing the digital frequency-control word;
- optional pull-range configuration if the selected OPN permits/runtime-requires it;
- fault reporting if the I2C device is absent or stops acknowledging;
- a zero-offset/default mode that leaves the TCXO at its factory nominal frequency.

## Exact integer timing at 120.9 MHz

With nominal frequency:

```text
system clock             120,900,000 Hz
ADC sample rate              930,000 Hz
system clocks/sample               130
samples/carrier cycle                 12
system clocks/carrier              1,560
system clocks/PRN chip          187,200
samples/PRN chip                   1,440
samples/second                    930,000
system clocks/second          120,900,000
```

This is a cleaner implementation basis than the previous 125 MHz + fractional sample-event scheme.

## ECP5 PLL operating point

A candidate fixed PLL arrangement is:

```text
CLKI        = 24.180 MHz
input divide = 1
feedback multiplication = 5
VCO / output-divider combination selected for legal ECP5 operation
CLKOP       = 120.900 MHz
```

The exact `EHXPLLL` divider parameters must be generated and validated with `ecppll`/Diamond against the ECP5 PLL legality rules. The architecture depends on the 24.18 -> 120.9 MHz relationship, not on hand-written primitive constants.

## Discipline loop

The carrier-phase estimator remains the error source.

Preferred control model:

```text
carrier phase
  -> unwrap
  -> impulse rejection / hole punching
  -> phase slope / frequency estimate
  -> very slow PI/FLL or Engeler-like search
  -> SiT5348 frequency offset word
```

Suggested states:

### Free run / startup

TCXO at nominal factory frequency. Even before DCF77 discipline, the ±50 ppb stability class is already inside the approximate ±0.1 ppm target reported for Engeler's disciplined clock.

### Acquisition

Use relatively short carrier averaging and estimate residual frequency error. Correction limits should be conservative; a Super-TCXO should not require tens of ppm correction.

### Tracking

After carrier lock, narrow the estimator bandwidth and apply tiny slow DCTCXO corrections.

### Holdover

Freeze the last trusted DCTCXO correction when DCF77 carrier confidence is lost. The Super-TCXO's intrinsic stability substantially improves holdover versus the low-cost quartz oscillator in the historical receiver.

## Relationship to `sample_scheduler.sv`

`rtl/core/sample_scheduler.sv` is **not deleted**.

It remains useful for:

- simulation of Engeler-like fractional correction;
- generic XO prototype boards;
- fallback if DCTCXO sourcing changes;
- fault/recovery experiments;
- comparison of fractional scheduling versus physically disciplined sampling.

For the preferred SiT5348 board, however, the normal ADC scheduler becomes an exact integer `/130` enable generator.

## EMI considerations

The TCXO frequency was deliberately selected for arithmetic coherence, so it is itself harmonically related to DCF77:

```text
24.18 MHz = 312 * 77.5 kHz
```

This is excellent mathematically but means clock leakage deserves serious board attention.

Mandatory layout rules:

- keep the TCXO and its 24.18 MHz trace far from the ferrite and input amplifier;
- do not route the clock beneath the antenna or first analog stages;
- keep the ECP5/TCXO region inside the digital partition;
- use controlled edge rate/drive if the chosen SiTime output option permits it;
- keep the clock trace short and avoid unnecessary stubs/test loops;
- provide a test point only where it will not create a large radiating stub;
- measure antenna spectra with TCXO/PLL/DSP activity enabled and disabled.

If harmonic self-interference becomes measurable, clock shielding/layout and randomized FPGA processing remain valid mitigation tools.

## Why SiT5348 rather than SiT5541 for Rev.0

The SiT5541 can provide even tighter ±10/±20 ppb stability, but uses a larger 7.0 x 5.0 mm package and is unnecessary for proving the Engeler receiver architecture.

The SiT5348 already provides:

- ±50 ppb stability;
- digital frequency control;
- 5.0 x 3.2 mm package;
- arbitrary 24.18 MHz programming;
- more than enough holdover performance for the initial receiver.

The PCB should therefore target SiT5348 first. A future ultra-precision board may evaluate SiT5541 if absolute holdover becomes a project requirement.

## Lifecycle policy

Treat the oscillator as a specified function, but document the SiT5348 as the preferred implementation.

Clock-source requirements are now:

```text
nominal frequency     24.180000 MHz preferred
stability             <= ±0.1 ppm; ±0.05 ppm preferred
supply                3.3 V preferred
output                LVCMOS preferred
frequency control     digital/I2C strongly preferred
pull range            >= ±1 ppm practical; ±6.25 ppm target
package               compact SMD
production lifecycle  active/production
```

If SiT5348 becomes unavailable, a new DCTCXO can replace it provided the clock architecture and tuning API are adapted without changing the DCF77 DSP core.

## Sources

- SiT5348 product page: https://www.sitime.com/products/ruggedized-timing/super-tcxos/sit5348
- SiT5348 data sheet: https://www.sitime.com/datasheet/SiT5348
- SiT5541 product page: https://www.sitime.com/products/ruggedized-timing/super-tcxos/sit5541
