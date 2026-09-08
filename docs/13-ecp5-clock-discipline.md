# ECP5 clock generation and DCF77 discipline

## Current preferred architecture

The initial rebuild plan used a generic 25 MHz XO, a fixed 125 MHz ECP5 clock, and a 40-bit fractional ADC sample scheduler.

That remains a valid fallback and simulation architecture, but the preferred hardware plan has improved after selecting a programmable SiTime Super-TCXO.

The Rev.0 target is now:

```text
SiTime SiT5348 DCTCXO
24.180000 MHz
        |
        v
ECP5 fixed PLL x5
        |
        v
120.900 MHz system clock
        |
        +--> exact /130 --> 930 kS/s ADC timing
        |
        +--> DCF77 DSP

DCF77 carrier phase
        |
        v
slow discipline loop
        |
        v
SiT5348 I2C digital frequency control
```

See [`15-sitime-super-tcxo.md`](15-sitime-super-tcxo.md) for the oscillator selection and detailed reasoning.

## Why 24.18 MHz is special

The target is mathematically coherent with DCF77:

```text
930 kHz     = 12 * 77.5 kHz
24.18 MHz   = 26 * 930 kHz
            = 312 * 77.5 kHz
120.90 MHz  = 5 * 24.18 MHz
            = 130 * 930 kHz
            = 1560 * 77.5 kHz
```

Therefore the ADC conversion interval can be exactly 130 system-clock cycles with no fractional event scheduling in the preferred implementation.

The system also retains exact sample-domain relationships:

```text
1 carrier cycle   = 12 ADC samples
1 PRN chip        = 1440 ADC samples
200 ms            = 186000 ADC samples
512 PRN chips     = 737280 ADC samples
1 second          = 930000 ADC samples
```

## Discipline philosophy

The ECP5 PLL remains **fixed**.

Do not continuously reprogram PLL divider values to follow DCF77.

Instead, the slow carrier-discipline controller commands the SiT5348 DCTCXO frequency through I2C. This adjusts the real clock source while the FPGA clock tree stays in a legal, stable PLL configuration.

This is closer to a conventional disciplined oscillator and removes the sample-event quantisation of the generic-XO plan.

## SiTime as the correction actuator

The carrier detector estimates phase. A persistent phase slope means the local clock is slightly fast or slow.

The clock loop is:

```text
carrier phase
    -> unwrap
    -> reject impulsive/outlier measurements
    -> estimate slow frequency error
    -> loop filter / search controller
    -> SiT5348 digital frequency-control word
```

The loop should run slowly, nominally once per second or slower in steady tracking.

The SiT5348 DCTCXO frequency-control response is fast relative to this loop: manufacturer data gives roughly 103 us typical command-to-frequency-change delay plus roughly 16.5 us typical settling time.

## Expected operating states

### Startup/free run

Run the SiT5348 at its factory nominal 24.18 MHz frequency.

The ±50 ppb stability class is already better than the approximate 0.1 ppm disciplined-clock target reported in Engeler's receiver, so the system starts from a very strong clock even before radio lock.

### Carrier acquisition

Use wider carrier estimator bandwidth and estimate residual phase slope.

Because the oscillator should already be close, apply conservative tuning limits. A requirement for multi-ppm correction should be treated as a diagnostic condition.

### Tracking

After carrier confidence is good:

- narrow the carrier estimator;
- update the SiTime frequency offset slowly;
- retain Engeler's impulse rejection/hole punching;
- avoid chasing short-term propagation phase variations;
- log commanded offset and phase residual for validation.

### Holdover

On carrier loss:

1. freeze the last trusted SiTime frequency correction;
2. continue local timing;
3. track holdover age/uncertainty;
4. reacquire carrier with a guarded transition;
5. resume corrections only after confidence is restored.

## Exact ADC timing

For the preferred clock plan:

```text
clk_sys = 120,900,000 Hz
Fs      =     930,000 Hz
ratio   =         130 clocks/sample
```

A simple modulo-130 counter can therefore produce `sample_ce`.

The ADC-specific wrapper converts `sample_ce` into the actual CNV/CONV pulse width and serial readout timing required by the chosen ADC.

The portable detector core must continue to see only sample events/data, not ADC electrical details.

## ECP5 PLL

The fixed PLL converts 24.18 MHz to 120.9 MHz.

The exact `EHXPLLL` primitive parameters must be generated/validated with the selected toolchain (`ecppll`, Project Trellis flow, or Lattice Diamond/Clarity) rather than manually assuming divider syntax.

The intended arithmetic relationship is fixed; primitive settings are an implementation detail.

## Fallback: generic XO + fractional scheduler

The repository retains [`../rtl/core/sample_scheduler.sv`](../rtl/core/sample_scheduler.sv).

The original fallback design is:

```text
25 MHz generic XO
 -> fixed ECP5 PLL
 -> 125 MHz
 -> 40-bit phase accumulator
 -> average 930 kS/s sample_ce
```

Its nominal increment is:

```text
8,180,366,511
```

and it provides extremely fine average-rate correction. It is useful for:

- boards without the SiTime DCTCXO;
- simulation/reference testing;
- comparing timing architectures;
- emergency BOM substitutions;
- algorithm development before final hardware.

It is no longer the preferred production timing path because the 24.18 MHz DCTCXO permits exact integer sample timing.

## Burst-noise protection

Engeler's hole-punching principle is retained regardless of clock actuator.

Atmospheric/lightning or local switching impulses can produce bad carrier-phase observations. A bad phase point must not cause a persistent oscillator correction.

Use:

```text
phase measurement
 -> quality/outlier check
 -> unwrap
 -> low-bandwidth frequency estimate
 -> actuator command
```

During poor carrier confidence, freeze rather than chase the measurement.

## Self-interference warning

24.18 MHz is deliberately an integer harmonic of DCF77:

```text
24.18 MHz = 312 * 77.5 kHz
```

That is ideal for timing arithmetic but potentially dangerous for an ultra-sensitive receiver if clock leakage reaches the ferrite antenna.

PCB requirements therefore include:

- strong physical separation between TCXO/ECP5 and the antenna/input stage;
- no clock routing under the analog front end;
- short clock traces;
- controlled output slew where available;
- quiet return paths;
- switcher/USB separation;
- antenna-spectrum measurements with digital subsystems toggled on/off.

Engeler's randomized/burst DSP scheduling may still be needed because digital processing activity can create coherent spurs even when the master oscillator itself is clean.

## Verification requirements

Before clock discipline is accepted:

1. validate legal ECP5 PLL configuration for 24.18 -> 120.9 MHz;
2. verify exactly 130 system clocks between nominal ADC conversion events;
3. validate SiT5348 I2C frequency-control writes on hardware;
4. measure oscillator frequency command resolution/linearity over the small range actually used;
5. measure command delay and transient impact;
6. acquire DCF77 carrier from known deliberate clock offsets;
7. verify loop convergence and residual phase slope;
8. inject impulsive phase errors and verify hole punching;
9. verify holdover/reacquisition behaviour;
10. measure clock-related spectral lines at the antenna input.

## Source documents

- Engeler receiver paper archived in this repository;
- Lattice ECP5 family data sheet and sysCLOCK PLL usage guide;
- SiTime SiT5348 product page and data sheet;
- [`15-sitime-super-tcxo.md`](15-sitime-super-tcxo.md) for the rebuild-specific oscillator plan.
