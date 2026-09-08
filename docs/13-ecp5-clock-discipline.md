# ECP5 clock generation and DCF77 discipline

## Decision

The rebuild will **not** continuously retune or reconfigure the ECP5 PLL to follow DCF77.

Instead, the clock architecture is split into three independent concepts:

1. a conventional fixed FPGA system clock;
2. a numerically controlled ADC sample scheduler;
3. a very slow DCF77 carrier-discipline loop that adjusts the scheduler increment.

This is the ECP5 equivalent of Engeler's occasional `d-1` / `d+1` divider correction, but it avoids disturbing the global FPGA clock tree.

The initial implementation target is:

```text
25.000 MHz LVCMOS XO
        |
        v
ECP5 sysCLOCK PLL
        |
        +---- 125.000 MHz fixed system clock
                    |
                    v
             fractional accumulator
                    |
                    +---- sample_ce / ADC CONV, average 930 kS/s
```

The FPGA logic continues running from the fixed 125 MHz clock. Only the **clock-enable / conversion-event timing** is fractionally advanced or delayed.

## Why not discipline the ECP5 PLL directly?

The ECP5 PLL is useful for producing a clean fixed processing clock, but continuously changing PLL parameters would make the DCF77 clock loop unnecessarily device-specific and would risk lock/relock transients.

Lattice specifies the ECP5 PLL with a 400-800 MHz VCO range and 10-400 MHz phase-detector range in the current family data sheet. A 25 MHz reference and 125 MHz output can use a 500 MHz VCO operating point, comfortably inside those limits.

A candidate divider set for a normal `EHXPLLL` configuration is:

```text
CLKI        = 25 MHz
CLKI_DIV    = 1
CLKFB_DIV   = 5
CLKOP_DIV   = 4
fPFD        = 25 MHz
fVCO        = 500 MHz
CLKOP       = 125 MHz
```

The exact primitive parameters must still be generated/checked with the selected ECP5 toolchain (`ecppll`, Diamond/Clarity, or equivalent) before the board bitstream is frozen.

Dynamic PLL phase adjustment is not required for the first receiver implementation.

## Why 125 MHz?

A 25 MHz oscillator is a common, easily multi-sourced board clock. Multiplication by five produces a processing frequency high enough to quantize ADC conversion instants finely without forcing the whole FPGA to run at an unnecessarily high EMI/power level.

At 125 MHz:

```text
system-clock period = 8 ns
ideal ADC period     = 1 / 930 kHz = 1075.268817... ns
ideal clocks/sample  = 125 MHz / 930 kHz
                     = 134.4086021505...
```

Therefore the ADC conversion scheduler naturally emits intervals of 134 or 135 system-clock periods. The phase accumulator ensures that the long-term average is exact to its numerical resolution and that timing error remains bounded to approximately one 125 MHz clock period.

This deliberately resembles Engeler's occasional one-clock timing correction rather than pretending that every physical ADC interval must be mathematically identical.

## 40-bit sample phase accumulator

A 40-bit accumulator is sufficient and deliberately avoids overengineering the first RTL version.

For a nominal 125 MHz system clock and 930 kS/s sample rate:

```text
NOMINAL_INC = round(2^40 * 930000 / 125000000)
            = 8,180,366,511
```

The resulting nominal sample rate is approximately:

```text
930000.0000394 samples/s
```

or only about:

```text
+0.000042 ppm
```

from the mathematical target.

One accumulator-LSB change corresponds to roughly:

```text
0.000122 ppm
```

of sample-rate correction.

This is already much finer than the ~0.003 ppm correction resolution reported for Engeler's demonstration receiver.

### Correction range

At this accumulator scaling:

```text
1 ppm correction ~= 8,180 increment counts
```

A signed 24-bit trim field therefore provides vastly more correction range than needed for an ordinary quartz oscillator while keeping the arithmetic small.

The recommended interface is conceptually:

```text
sample_increment = NOMINAL_INC + signed_trim
```

with `signed_trim` updated only by the slow carrier-discipline loop.

## Timing quantisation and jitter budget

The fractional scheduler places each ideal sample instant on the nearest reachable 8 ns clock grid through its accumulated phase.

For a simple bounded/uniform timing-error estimate, one 8 ns quantisation interval corresponds to about 2.31 ns RMS timing uncertainty.

At a 77.5 kHz input carrier, this is approximately a **59 dB jitter-limited SNR** estimate:

```text
SNR_jitter ~= -20 log10(2*pi*fcarrier*sigma_t)
```

The maximum one-system-clock carrier phase interval is only about:

```text
8 ns / (1 / 77.5 kHz) * 360 deg ~= 0.223 deg
```

This is in the same engineering spirit as Engeler's deliberately non-uniform divider correction, for which the paper estimated a roughly 50 dB clock-jitter ceiling. The real prototype must still measure this rather than relying only on the calculation.

The ECP5 PLL's own specified clock jitter is far smaller than the 8 ns scheduler quantisation, so the scheduler and the board oscillator dominate this particular timing budget.

## DCF77 integer relationships retained in the sample domain

Once the **average sample rate is disciplined to 930 kS/s**, all important DCF77 ratios remain exact integer relationships in sample count:

```text
carrier period:
    12 samples

PRN chip duration:
    120 carrier periods
    = 1440 ADC samples

200 ms PRN start offset:
    186000 ADC samples

512-chip PRN duration:
    512 * 1440
    = 737280 ADC samples

PRN end position:
    186000 + 737280
    = 923280 samples
    = 992.7741935... ms

one nominal second:
    930000 samples
```

This is extremely useful: the FPGA can express all carrier/PRN timing in the **disciplined sample domain**, while the 125 MHz system clock remains merely an implementation clock.

Do not generate the PRN chip timing from an unrelated free-running 645.833 Hz divider. Generate it from second-phase/sample position so that the phase code remains coherent with the receiver's DCF77 timebase.

## Proposed RTL boundary

The first clock-control layer should provide:

```text
clk_sys_125m       fixed FPGA clock
pll_locked         fixed PLL status
sample_ce          one-cycle pulse for each ADC conversion event
sample_trim        signed rate correction
sample_phase       optional debug accumulator state
```

Later timing logic derives:

```text
carrier_sample_phase  modulo 12 sample position
second_sample_phase   0 .. 929999 after second lock
prn_chip_index        0 .. 511 while the PZF window is active
```

Keep those counters out of the PLL wrapper. They belong to the portable DCF77 core.

## ADC implications

This architecture is especially well suited to a SAR ADC with a `CONV`/`CNV` input:

- `sample_ce` schedules the conversion edge;
- the ADC serial clock can remain a conventional fixed/divided FPGA clock;
- sample timing and serial readout timing are separated;
- the DCF77 discipline loop never touches the ECP5 global system clock.

The final ADC must be checked for minimum conversion spacing and serial-readout completion at the shortest scheduler interval (134 system-clock periods, about 1.072 us).

## Carrier-discipline loop

### Observable

The detector provides a carrier phase estimate. A persistent slope in measured phase versus local time indicates sample-clock frequency error.

A 1 ppm local timing-rate error corresponds to approximately:

```text
77,500 carrier cycles/s * 1e-6
= 0.0775 carrier cycles/s
= 27.9 degrees/s
```

so even a modest phase estimator has substantial leverage for measuring quartz error.

### Loop structure

Use two operating states.

#### Acquisition

- begin with the nominal accumulator increment;
- permit a wide correction range (at least +/-100 ppm);
- average carrier phase over short windows;
- reject impulsive phase measurements before they affect frequency control;
- estimate the phase slope and drive the sample increment toward zero slope.

This stage replaces the coarse part of Engeler's binary-search clock correction.

#### Tracking

After stable carrier lock:

- narrow the carrier estimator bandwidth;
- update `sample_trim` slowly (nominally once per second or slower);
- use a low-bandwidth PI/FLL-style controller or a paper-compatible binary-search controller;
- slew correction rather than making large instantaneous changes;
- freeze or heavily damp correction during carrier dropouts.

Exact loop coefficients are **not yet frozen**. They must be selected from simulation and recorded receiver captures because the phase-noise statistics depend strongly on RF conditions.

## Hole-punching / impulse rejection

Retain Engeler's important clock-loop protection:

```text
carrier phase
    -> unwrap
    -> reject/mute implausibly large single-sample deviations
    -> slow frequency estimator
    -> sample_trim
```

A lightning impulse or local switching event must not permanently pull the disciplined clock.

The decoder may tolerate one corrupted second; a corrupted clock estimate can poison many seconds.

## Holdover behaviour

When carrier lock is lost:

1. freeze the last trusted `sample_trim`;
2. continue timekeeping from the local XO;
3. increase an uncertainty/holdover-age metric;
4. reacquire carrier phase without an abrupt time jump;
5. only resume normal tracking after phase measurements pass confidence checks.

A TCXO is therefore optional rather than mandatory. A normal quartz XO should already be adequate for receiver development because DCF77 continuously disciplines it; a TCXO only improves long holdover periods.

## Oscillator lifecycle strategy

Do not lock the PCB to a rare DCF77-related oscillator frequency.

Use a **standard 25 MHz LVCMOS oscillator** and treat the oscillator as a replaceable BOM item with electrical requirements rather than a magic part number.

Initial requirements:

```text
frequency       25.000 MHz
supply          3.3 V preferred
logic           LVCMOS
initial accuracy <= +/-25 ppm preferred
industrial-temp option desirable
low phase jitter preferred
output enable   useful but not mandatory
```

PCB recommendations:

- use a common 4-pad oscillator footprint selected during schematic capture;
- provide a 0-ohm option or mux point for an external clock source;
- expose a clock test point away from the ferrite antenna;
- keep the XO and FPGA clock traces physically far from the antenna/JFET input;
- avoid routing any 25/125 MHz line under the analog input section.

The production BOM should have at least two approved oscillator sources before the board is declared lifecycle-safe.

## EMI consequences

The system clock no longer needs to be an exact harmonic of 77.5 kHz, which is beneficial from a self-interference perspective.

However, the ADC conversion pattern is still DCF77-related and digital activity can still create deterministic spectral lines. Therefore Engeler's randomised/burst processing concept remains relevant even with the ECP5 design.

During RF bring-up, compare antenna spectra in at least these modes:

1. FPGA configured but DSP idle;
2. ADC scheduler running;
3. carrier/Goertzel processing running continuously;
4. randomised/burst DSP scheduling enabled;
5. USB/debug traffic enabled/disabled.

Self-interference at or close to 77.5 kHz is a board acceptance criterion, not a cosmetic EMC issue.

## Verification plan

Before this clock architecture is considered complete:

1. simulate the accumulator for several billion system clocks or an equivalent mathematical model;
2. verify sample count and bounded phase error;
3. sweep `sample_trim` across at least +/-100 ppm;
4. confirm monotonic frequency response and absence of accumulator overflow pathologies;
5. run the carrier detector against synthetically clock-offset DCF77 captures;
6. verify acquisition from at least +/-50 ppm;
7. inject burst phase errors and confirm hole-punching behaviour;
8. measure actual `CONV` jitter on hardware;
9. measure carrier-phase noise with the clock loop open and closed;
10. measure FPGA/XO self-interference at the ferrite input.

## Source documents

Primary ECP5 clock references:

- Lattice `FPGA-DS-02012`, **ECP5 and ECP5-5G Family Data Sheet**;
- Lattice `FPGA-TN-02200`, **ECP5 and ECP5-5G sysCLOCK PLL/DLL Design and Usage Guide**;
- Project Trellis `ecppll` utility/source, used by the open ECP5 toolchain to calculate legal PLL divider sets.

The clock-discipline concept itself is derived from Engeler's receiver architecture; the fixed-PLL plus fractional-sample-scheduler implementation is a new reconstruction choice for this repository.