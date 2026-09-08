# Rev.0 fixed TCXO selection and clock architecture

## Decision

Rev.0 now freezes the clock source as a **simple fixed TCXO**:

```text
SiTime SiT5356AI-FQ-33E0-25.000000
25.000000 MHz
TCXO, fixed frequency
3.3 V
LVCMOS
±100 ppb frequency stability
-40 ... +85 degC
5.0 x 3.2 mm, 10-CQFN
```

Digi-Key listed this exact 25 MHz / 3.3 V / ±100 ppb TCXO as an active catalogue part in the September 2026 sourcing check, with approximately 3500 factory/value-added units shown.

This is now the Rev.0 reference OPN, subject only to the normal BOM-release rule that distributor availability must be rechecked immediately before procurement.

DCF77 discipline remains digital inside the ECP5/sample-time architecture. A DCTCXO is not required for the reference receiver.

## Why this exact part

The selected part satisfies the project selection order:

1. stability is already in the same 100 ppb class as Engeler's final disciplined-clock target;
2. exact OPN is orderable through a major distributor rather than being only a factory-programming concept;
3. 25 MHz is a standard frequency;
4. 3.3 V LVCMOS fits the dedicated `3V3_CLK` rail and ECP5 clock input;
5. -40...+85 degC is suitable for the intended industrial-temperature Rev.0 design;
6. the frequency is not an integer harmonic of the 77.5 kHz wanted carrier;
7. the existing 125 MHz ECP5 clock/scheduler study already works naturally from a 25 MHz reference.

The selected fixed TCXO and the previously considered DCTCXO are in a similar high-precision cost class, but the fixed part avoids a control protocol and makes the reference architecture simpler and more vendor-independent at the RTL level.

## Why 25 MHz instead of 24.18 MHz

The old arithmetic study used:

```text
24.18 MHz = 312 * 77.5 kHz
```

which made integer clock ratios attractive but also made the board clock exactly harmonically related to the extremely weak RF carrier.

The selected clock instead has:

```text
25 MHz / 77.5 kHz ~= 322.580645...
```

There is no exact integer relationship.

That is preferable for a weak-signal receiver because deterministic clock leakage is less likely to sit coherently on the wanted carrier simply by construction.

## System-clock plan

Reference digital clock plan:

```text
SiT5356 TCXO
25 MHz
   |
   v
ECP5 sysCLOCK PLL
   |
   v
125 MHz nominal system clock
```

The final EHXPLLL divider/phase configuration must be generated and checked with the pinned ECP5 toolchain, but 25 MHz is the reference input frequency for all Rev.0 clock planning.

The ECP5-45 device provides four general-purpose PLLs; the receiver reference build uses only the resources needed to stay inside the historical clock-manager policy.

## ADC sample scheduler

The ADC does not require a physical 930 kHz clock from the TCXO.

At a 125 MHz system clock, the existing 40-bit fractional event scheduler produces the average target:

```text
Fs = 930,000 samples/s
```

Reference nominal accumulator increment:

```text
PHASE_BITS = 40
INC_NOMINAL = 8,180,366,511
```

The ideal number of 125 MHz clocks per sample is:

```text
125,000,000 / 930,000
= 134.4086021505...
```

so the scheduler naturally alternates bounded 134/135-clock sample intervals while maintaining the correct long-term average.

The numerical increment quantization is far finer than the receiver's required frequency correction and is not the limiting timing error.

Reference implementation:

```text
rtl/core/sample_scheduler.sv
```

## Digital DCF77 discipline

The physical TCXO remains fixed.

The carrier-tracking loop estimates the local fractional frequency error and applies it to the digital time/sample scheduler:

```text
25 MHz fixed TCXO
     |
     v
125 MHz fixed nominal clock
     |
     v
fractional scheduler + digital frequency trim
     |
     +--> ADC CONV timing
     +--> receiver second timebase
     +--> PPS timebase
```

This follows the same broad philosophy as Engeler: the receiver estimates clock error from DCF77 and corrects its digital timebase rather than requiring an ovenized or physically steered local oscillator.

## Holdover

The TCXO specification gives a useful conservative bound before any learned correction is considered.

For `100 ppb`:

```text
100 ns / second
360 us / hour
8.64 ms / day
```

When carrier lock is lost:

1. freeze the last trusted digital frequency-correction estimate;
2. continue from the fixed TCXO;
3. increase holdover age/uncertainty;
4. keep PPS monotonic;
5. reacquire carrier phase without an abrupt time jump;
6. resume tracking only after confidence checks pass.

The actual holdover after prior DCF77 calibration can be materially better than the raw ±100 ppb worst-case number, but that improvement must be measured rather than assumed.

## Dedicated power rail

The selected TCXO is powered only from:

```text
5V_SYS
  -> TPS7A20 3.3 V low-noise LDO
  -> 3V3_CLK
  -> SiT5356AI-FQ-33E0-25.000000
```

Do not share the final clock regulator with the ADC.

Clock output edge currents and ADC sampling currents should have separate local supply/return paths.

## Output routing

Use one dedicated ECP5 clock-capable input pin.

Placement/routing rules:

- TCXO and TPS7A20 form one compact timing island;
- keep the 25 MHz trace short and referenced to continuous ground;
- no 25 MHz trace under or adjacent to the integrated ferrite/input node;
- no clock trace through the LTC1562/PGA region;
- place a source-series damping footprint close to the TCXO output if required by the selected drive-strength configuration;
- do not route the clock to unused connectors or test headers as a long stub.

A local high-impedance test point may be included only if its stub is extremely short and accounted for in the layout.

## Enable behavior

The exact feature-pin strapping follows the selected SiTime ordering code and data sheet.

Reference policy:

```text
TCXO enabled whenever 3V3_CLK is valid
```

The receiver should not repeatedly gate the master TCXO during normal operation.

## DCTCXO status

DCTCXO is now **experimental only**.

The previously researched SiT5356 DCTCXO variants remain useful for a future comparison board because the package family is similar, but the reference receiver has no need for digital oscillator steering.

A DCTCXO should only be promoted into the reference BOM if measured data shows a material improvement in:

- long holdover;
- PPS phase noise;
- temperature transient recovery;
- sample-timing quality;
- or another system-level metric.

## Validation gates

The OPN and nominal frequency are fixed; measurements validate the design rather than choose a different frequency per board.

Measure:

1. 25 MHz frequency at room temperature before DCF77 correction;
2. warm-up behavior after power-on;
3. PPS drift during 1 h carrier-loss holdover;
4. short-term phase noise/jitter contribution to ADC timing;
5. conducted noise on `3V3_CLK`;
6. ferrite spectrum with the TCXO enabled and disabled;
7. 25 MHz / PLL-related spurs around 77.5 kHz;
8. 125 MHz PLL lock/relock behavior across repeated power cycles.

A failed EMI validation should be solved by placement, edge control, shielding/return geometry or clock-plan implementation before reopening the oscillator frequency itself.

## Current reference clock chain

```text
SiT5356AI-FQ-33E0-25.000000
25 MHz, 3.3 V, ±100 ppb
  -> ECP5 PLL
  -> 125 MHz nominal system clock
  -> 40-bit fractional sample/time scheduler
  -> DCF77 digital frequency correction
  -> hardware PPS
```

## Sources

- SiTime SiT5356 family/current ordering information.
- Digi-Key September 2026 exact-OPN sourcing snapshot.
- Lattice ECP5/ECP5-5G sysCLOCK PLL/DLL design guide.
- Engeler DCF77 receiver paper archived in this repository.
