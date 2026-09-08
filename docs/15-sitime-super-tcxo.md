# Clock-source selection: precision, availability and frequency

## Status

No SiTime part number or custom frequency is frozen yet.

The previous `SiT5348 @ 24.180000 MHz` proposal is retained only as an arithmetic study. It is **not** the production choice, because the clock source must be selected from the combination of:

1. required final timing/holdover performance;
2. real distributor availability of an exact orderable OPN;
3. temperature range and supply/output compatibility;
4. pull/control mechanism for DCF77 discipline;
5. PLL legality and sample-clock implementation;
6. EMI/self-interference risk;
7. lifecycle and second-source strategy.

A mathematically convenient custom frequency is not sufficient justification by itself.

## Precision requirement comes first

Engeler reports a disciplined local-clock target around `0.1 ppm`, i.e. about `100 ppb`.

Useful free-run/holdover intuition:

| Oscillator stability | worst-case time drift per second | worst-case drift per day |
|---:|---:|---:|
| ±500 ppb | ±500 ns/s | ±43.2 ms/day |
| ±250 ppb | ±250 ns/s | ±21.6 ms/day |
| ±100 ppb | ±100 ns/s | ±8.64 ms/day |
| ±50 ppb | ±50 ns/s | ±4.32 ms/day |
| ±20 ppb | ±20 ns/s | ±1.728 ms/day |

The final synchronized timing accuracy is not determined by the TCXO alone. It will also be limited by propagation, ferrite-antenna phase/group delay, analog-filter group delay, carrier phase estimation, calibration and receiver noise.

Therefore the current design rule is:

```text
baseline oscillator class: <= ±100 ppb
preferred only if justified: ±50 ppb or better
```

A ±100 ppb DCTCXO already matches the order of magnitude of Engeler's final disciplined-clock target. A ±50 ppb device is valuable mainly for better holdover and for a future tighter absolute-time target.

## Distributor availability snapshot

Availability must be checked again at BOM freeze; the following is only a dated engineering snapshot from Digi-Key on 2026-09-08.

### Candidate A — 25 MHz, 3.3 V

```text
SiTime SiT5356AC-FQG33IT-25.000000
DCTCXO
25.000000 MHz
3.3 V LVCMOS
±100 ppb
APR ±5.31 ppm
-20 ... +70 °C
Digi-Key: ~3502 factory stock at snapshot
```

Advantages:

- standard 25 MHz frequency;
- 3.3 V LVCMOS;
- useful narrow pull range;
- direct fit with the existing 25 -> 125 MHz ECP5 clock study;
- strong factory-stock depth at the snapshot.

Disadvantage: the exact stocked OPN found is not industrial-temperature grade.

### Candidate B — 26 MHz, 2.5 V

```text
SiTime SiT5356AI-FQC25IE-26.000000
DCTCXO
26.000000 MHz
2.5 V LVCMOS
±100 ppb
APR ±100 ppm
-40 ... +85 °C
Digi-Key: ~3502 factory stock at snapshot
```

Advantages:

- industrial temperature range;
- strong stock depth;
- 26 MHz is a very common catalogue clock frequency;
- ECP5 can use a convenient 130 MHz processing clock with a x5 plan if legal divider settings are confirmed.

Disadvantages:

- requires a clean 2.5 V oscillator rail;
- pull range is much wider than required for DCF77 discipline.

### Candidate C — 10 MHz, 3.3 V

Example stocked ±100 ppb family member:

```text
SiTime SiT5356AE-FQ033JT-10.000000
DCTCXO
10.000000 MHz
3.3 V LVCMOS
±100 ppb
APR ±5.31 ppm
-40 ... +105 °C
Digi-Key: ~6585 factory stock at snapshot
```

Advantages:

- excellent distributor/factory-stock depth;
- standard precision-reference frequency;
- 3.3 V;
- extended industrial temperature range;
- narrow pull range suitable for discipline.

Disadvantage: 10 MHz places the ECP5 PLL phase-detector frequency near the lower end of the family specification in some clock plans, so the final PLL configuration must be checked carefully rather than assumed.

### Candidate D — 24.576 MHz, 3.3 V

A Digi-Key-listed SiT5356 DCTCXO exists at 24.576 MHz and ±100 ppb, but only single-digit immediate stock was visible at the snapshot. This makes it a poor primary choice despite the familiar telecom/audio frequency.

## Why SiT5348 is no longer the default

The SiT5348 remains technically excellent and is still a valid candidate if the final timing/holdover requirement justifies it. Its ±50 ppb class, excellent dynamic behaviour and fine digital tuning are attractive.

However:

- the Endura part is a premium ruggedized component;
- the previous 24.18 MHz proposal relied on custom programming rather than a deeply stocked catalogue OPN;
- a stocked ±100 ppb SiT5356 DCTCXO already matches the order of magnitude of the receiver's current target;
- distributor depth is part of the design requirement, not an afterthought.

Therefore `SiT5348` is now an **upper-performance candidate**, not the default.

## Frequency-selection policy

The clock frequency will be selected in this order:

1. choose an exact stocked DCTCXO OPN meeting stability/temperature requirements;
2. prefer standard catalogue frequencies with multiple distributor/factory-stock paths;
3. verify ECP5 PLL legality and jitter;
4. derive 930 kS/s with either an integer divider or the already-designed fractional scheduler;
5. evaluate spectral relationships to 77.5 kHz and reject frequencies that create unacceptable receiver self-interference;
6. only request a custom SiTime frequency if it provides a measured system benefit that outweighs sourcing risk.

## Important EMI correction to the 24.18 MHz idea

The 24.18 MHz study has the relation:

```text
24.18 MHz = 312 * 77.5 kHz
```

That is attractive mathematically but potentially unattractive electromagnetically: the board clock is exactly harmonically related to the wanted carrier.

For this weak-signal receiver, avoiding a deterministic clock/carrier relationship can be more valuable than eliminating a few nanoseconds of sample-scheduler quantization.

This is another reason to prefer a normal stocked frequency such as 25 or 26 MHz unless measurements prove otherwise.

## Sample-clock consequence

A standard stocked frequency does not prevent DCF77 discipline.

With a fixed NCO/sample scheduler:

```text
f_sample = f_system * INC / 2^N
```

If a DCTCXO adjustment changes `f_system` by a small relative amount, the generated sample rate changes by the same relative amount. Therefore the DCTCXO can still be the physical frequency actuator while the fractional scheduler preserves the desired nominal 930 kS/s ratio.

The existing portable module remains useful:

```text
rtl/core/sample_scheduler.sv
```

The normal design should therefore accept a few-nanosecond bounded scheduling quantization if that buys much better oscillator availability and EMI behaviour.

## Decision gate before schematic freeze

Do not place a final oscillator OPN in the production BOM until we have written down:

```text
absolute synchronized timing target
required holdover duration
allowed holdover time error
board operating-temperature range
required DCTCXO pull range
acceptable supply rail(s)
minimum distributor/factory stock depth
maximum oscillator BOM cost
```

The likely baseline is currently **SiT5356 DCTCXO, ±100 ppb class, standard stocked frequency**, but exact frequency/OPN remains open.
