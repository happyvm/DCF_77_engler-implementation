# Rev.0 fixed 77.5 kHz LTC1562 band-pass

## Decision

Rev.0 uses a **fixed, no-trim** 8th-order LTC1562 continuous-time band-pass derived directly from Analog Devices' published high-frequency band-pass application.

The reference build does not require per-board resistor selection, trimmers or frequency alignment.

Preferred IC for Rev.0:

```text
Analog Devices LTC1562IG#PBF
20-pin SSOP
industrial temperature grade
continuous-time active RC filter
4 independent 2nd-order sections
single 5 V operation
```

The LTC1562 family is currently listed by ADI as `PRODUCTION`.

> **OPEN VERIFICATION (2026-09-12).** The resistor values below are scaled *linearly* from an
> ADI high-frequency band-pass table that is not reproduced here. The LTC1562 data sheet
> (`1562fa`) gives `fO = 1 / (2*pi*C*sqrt(R1*R2))` with `R1 = 10k` and `C = 159 pF` internal,
> and `Q = RQ / sqrt(R1*R2)`. Those formulas put `R2 = 12.8k` at `fO ~= 88.5 kHz` and
> `Q ~= 4.2`, i.e. ~14 % above the 77.5 kHz target and roughly a 21 kHz -3 dB bandwidth rather
> than 7.75 kHz. Reaching 77.5 kHz needs `R2 ~= 16.65k`; `Q = 10` then needs `RQ ~= 129k`.
> The data sheet does not contain the `RIN1 = 4.64k / RQ1 = 46.4k / R21 = 12.4k` row, so the
> source table still has to be located before these values are frozen. The schematic
> (`hardware/tscircuit/src/core/afe.tsx`) keeps these values unchanged; see
> `hardware/tscircuit/README.md -> "Schematic-freeze status (Rev.0)"`.

A September 2026 Digi-Key snapshot showed roughly 400 pieces of `LTC1562IG#PBF` immediately available. The tighter A-grade parts remain in production but are less consistently stocked. Because the required analog passband is intentionally much wider than the IC's center-frequency tolerance, Rev.0 prioritizes the stocked industrial standard grade.

## Manufacturer reference topology

ADI publishes an 8th-order high-frequency band-pass using all four LTC1562 sections with:

```text
-3 dB bandwidth = fCENTER / 10
overall gain     = 10
```

At `fCENTER = 80 kHz`, ADI gives:

```text
Side B:
RIN1 = 4.64 kOhm
RQ1  = 46.4 kOhm
R21  = 12.4 kOhm

Sides A, C, D:
RIN2 = RIN3 = RIN4 = 46.4 kOhm
RQ2  = RQ3  = RQ4  = 46.4 kOhm
R22  = R23  = R24  = 12.4 kOhm
```

The manufacturer table permits ±1% resistors. Rev.0 uses tighter standard values because they are inexpensive and remove external resistor tolerance as a meaningful contributor.

## Scaling to exactly 77.5 kHz

Frequency-programming resistors scale inversely with center frequency.

Use:

```text
scale = 80 / 77.5
      = 1.0322580645...
```

This gives:

| Function | 80 kHz ADI value | Exact scaled target | Rev.0 fitted value |
|---|---:|---:|---:|
| `RIN1` | 4.64 kOhm | 4.78968 kOhm | **4.79 kOhm** |
| `RQ1` | 46.4 kOhm | 47.8968 kOhm | **47.9 kOhm** |
| `R21` | 12.4 kOhm | 12.8000 kOhm | **12.8 kOhm** |
| `RIN2/3/4` | 46.4 kOhm | 47.8968 kOhm | **47.9 kOhm** |
| `RQ2/3/4` | 46.4 kOhm | 47.8968 kOhm | **47.9 kOhm** |
| `R22/23/24` | 12.4 kOhm | 12.8000 kOhm | **12.8 kOhm** |

The fitted errors are negligible:

```text
4.79k versus target 4.78968k  ~= +0.0067%
47.9k versus target 47.8968k ~= +0.0067%
12.8k versus target          = exact at displayed precision
```

There is therefore no reason to use series resistor combinations or custom values.

## Resistor specification

Use one thin-film resistor technology across all frequency/Q/gain-setting positions:

```text
tolerance     <= 0.1%
tempco        <= 25 ppm/degC preferred
package       0603 preferred
technology    thin film
```

Exact manufacturer OPNs may vary with sourcing, but the resistance values are fixed.

Reference values:

```text
4.79 kOhm  0.1%
47.9 kOhm  0.1%
12.8 kOhm  0.1%
```

Do not substitute 1% values in the reference BOM merely because the original ADI application allowed them; the 0.1% values are standard and cheap enough to remove an unnecessary source of variation.

## Resulting analog response target

Nominal center:

```text
fCENTER = 77.5 kHz
```

Nominal -3 dB bandwidth:

```text
BW = 77.5 kHz / 10
   = 7.75 kHz
```

Approximate half-power edges:

```text
73.625 kHz ... 81.375 kHz
```

Nominal filter gain:

```text
10 V/V = 20 dB
```

This analog bandwidth is intentionally much wider than the final digital DCF77 detector bandwidth.

The antenna/input network is already broadened to a few kilohertz, while the LTC1562 provides stronger out-of-band rejection without collapsing the PM/PZF information into an AM-only narrowband path.

## Why the standard LTC1562 grade is sufficient

The LTC1562 SSOP center-frequency error is specified approximately as:

```text
standard grade: typical ~0.5%, maximum ~1.0%
A grade:        typical ~0.3%, maximum ~0.6%
```

At 77.5 kHz, a ±1% center-frequency error is only:

```text
±775 Hz
```

Compared with the nominal half-power half-width:

```text
7.75 kHz / 2 = 3.875 kHz
```

Thus the wanted 77.5 kHz carrier remains comfortably inside the analog passband even at the standard-grade center-frequency limit.

The A-grade device remains electrically compatible and may be populated if equally available, but it is **not required** for the reference receiver and should not become a sourcing dependency.

## Temperature behavior

ADI reports a typical LTC1562 center-frequency temperature coefficient around `-25 ppm/degC` over its industrial range.

This is small compared with the deliberately broad 7.75 kHz analog passband.

Use matched low-tempco external resistors so resistor drift does not unnecessarily add to the IC's intrinsic drift.

No temperature-dependent resistor or capacitor correction is required in the reference BOM.

## Supply and analog-ground configuration

The LTC1562 runs from the low-loss filtered `5V_AFE` rail:

```text
V+ = 5V_AFE
V- = GND
```

The IC creates its own mid-supply analog reference at `AGND`, nominally `V+/2`, through an internal divider. ADI specifies an equivalent source resistance around 7 kOhm.

For single-supply operation:

```text
AGND -> at least 1 uF local bypass to quiet ground
V+   -> 100 nF local bypass, plus nearby bulk support
SHDN -> logic low referenced to V- for normal operation
```

Do not connect `SHDN` to `AGND`; ADI explicitly requires the single-supply logic-low state to be `V-`.

The antenna buffer's `VCM_AFE` and the LTC1562 `AGND` are both nominally around 2.5 V but are separate functional nodes unless the final schematic deliberately buffers/links them. Do not casually use the LTC1562 AGND pin as a general-purpose current source for the upstream AFE because its internal midpoint has finite source impedance.

## Interface from OPA810

The upstream OPA810 buffer preserves the fixed antenna tuning and produces a low-impedance 77.5 kHz signal centered near `VCM_AFE`.

The final AFE schematic should ensure that the LTC1562 input has the correct DC operating point without changing the published resistor network.

Preferred policy:

```text
OPA810 output
  -> AC coupling / bias interface if required
  -> RIN1 = 4.79 kOhm
  -> LTC1562 8th-order network
```

Any coupling capacitor belongs to the DC-interface design, not the filter-frequency programming. Its reactance at 77.5 kHz must be negligible compared with `RIN1` and it must not be used as a tuning element.

## Placement constraints

Treat the LTC1562 and all eleven external programming resistors as one analog cluster.

Quilter constraints:

- place the resistor network immediately around the LTC1562 pins;
- keep section-to-section nodes short;
- keep the filter physically downstream of OPA810 and upstream of LTC6912;
- no buck switch node, ECP5 clock, ADC SCK, USB or Raspberry Pi fast trace through the filter area;
- use a continuous ground reference with current-path control by placement;
- bypass `AGND` locally with a short return;
- do not route digital return current through the LTC1562/antenna corridor.

## No-trim production policy

The reference BOM is fixed:

```text
RIN1                  4.79 kOhm 0.1%
RQ1                   47.9 kOhm 0.1%
R21                   12.8 kOhm 0.1%
RIN2, RIN3, RIN4      47.9 kOhm 0.1%
RQ2, RQ3, RQ4         47.9 kOhm 0.1%
R22, R23, R24         12.8 kOhm 0.1%
```

No potentiometer.
No trimmer capacitor.
No per-board resistor binning.
No measured-value substitution.

Engineering validation may measure the filter response of prototype boards, but those measurements verify the design; they do **not** determine component values for individual boards.

## Rev.0 AFE after this decision

```text
TDK B82453C0275A000 X winding
  || 560 pF C0G
  || 22 pF C0G
  || 330 kOhm
       |
       v
OPA810 voltage follower
       |
       v
LTC1562IG#PBF
8th-order BPF
77.5 kHz / 7.75 kHz BW / gain 10
fixed 0.1% resistors
       |
       v
LTC6912 PGA
       |
       v
OPA2835 / LTC1407A-1
```

## Sources

- Analog Devices LTC1562 product page, current lifecycle status.
- Analog Devices LTC1562 data sheet, 8th-order high-frequency band-pass application and electrical characteristics.
- Analog Devices Design Note 195, external-resistor frequency sensitivity.
- September 2026 Digi-Key/Mouser availability snapshots; stock quantities are dated observations and must be rechecked at BOM release.
