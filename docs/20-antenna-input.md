# Rev.0 integrated DCF77 antenna and fixed tuning network

## Decision

Rev.0 will not require per-board antenna trimming or empirical resistor/capacitor selection.

The integrated antenna path is designed from component tolerances so that 77.5 kHz remains inside the useful antenna passband without hand tuning.

Preferred antenna:

```text
TDK B82453C0275A000
3D ferrite transponder coil
12.5 x 11.5 x 3.6 mm
AEC-Q200
Production
```

For the primary DCF77 channel use the **X winding only**:

```text
Lx = 7.2 mH ±3% @ 125 kHz
Qx typ = 23.5 @ 125 kHz
Sensitivity X typ = 80 mV/uT @ 125 kHz
```

The Y and Z windings remain open in Rev.0. They are not shorted, because shorting an unused orthogonal winding could magnetically load the active axis.

TDK specifies this family at 125 kHz, so use at 77.5 kHz is a deliberate reconstruction extrapolation. The component's self-resonance is far above DCF77, and the external resonance is deliberately broadened to tolerate component variation.

## Why this part instead of the smaller B82450A7204A000

The smaller one-axis TDK B82450A7204A000 is also production and attractive mechanically, but its typical sensitivity is only about 52 mV/uT and its minimum Q is 40 at 125 kHz.

For a no-trim design that higher Q is a disadvantage because ±3% inductance tolerance shifts the resonance significantly compared with the narrow antenna bandwidth.

The B82453C0275A000 X winding gives:

- higher typical sensitivity: about 80 mV/uT at 125 kHz;
- lower, more useful Q around 23.5;
- 7.2 mH ±3% inductance;
- a wider intrinsic resonant bandwidth;
- a package still small enough for direct PCB mounting;
- strong distributor stock at the September 2026 snapshot.

The unused axes are accepted as the cost of obtaining a better integrated ferrite geometry and a more tolerant receive network.

## Fixed resonance network

The ideal total capacitance for 7.2 mH at 77.5 kHz is approximately:

```text
Ctotal = 1 / ((2*pi*77500)^2 * 7.2 mH)
       ~= 586 pF
```

The input buffer and PCB add a few picofarads. Rev.0 intentionally budgets about 4 pF total input/PCB capacitance and therefore uses:

```text
CANT1 = 560 pF C0G/NP0, 1%
CANT2 = 22 pF  C0G/NP0, 1%

Cfixed = 582 pF
Cparasitic target ~= 4 pF
Ctotal nominal ~= 586 pF
```

No trimmer capacitor is fitted in the reference BOM.

Do not add an optional large pad or long antenna stub at this node unless its capacitance is included in the budget.

## Fixed damping resistor

A very high-Q antenna would maximize resonant voltage but would make a no-trim design too sensitive to inductance, capacitor, PCB and temperature variation.

Rev.0 deliberately sets a wider loaded antenna response with:

```text
RANT = 330 kOhm, 1%, thin-film
```

connected in parallel with the tuned coil/capacitor network.

At 77.5 kHz with 7.2 mH:

```text
X_L ~= 3.51 kOhm
Q_parallel_from_330k ~= 94
```

Combined with the TDK X-axis Q around 23.5, the resulting nominal loaded Q is roughly:

```text
Q_loaded ~= 19
BW ~= 77.5 kHz / 19
   ~= 4.1 kHz
```

Using the TDK published Q tolerance around the typical value gives an expected loaded-Q region of roughly 17 to 21, corresponding to about 3.7 to 4.5 kHz total -3 dB bandwidth.

This is intentional. The antenna is not supposed to be the final narrow detector; the LTC1562 and digital detector perform downstream filtering. The antenna network should preserve the DCF77 PM information and remain tolerant enough that production boards do not need hand alignment.

## Tolerance check

The fixed network is chosen so that the wanted 77.5 kHz carrier remains within the approximate antenna half-power band across the main deterministic tolerances.

Assumptions used for the design envelope:

```text
Lx                 ±3%
Cfixed             ±1%
OPA810 + PCB Cin   approximately 3 to 6 pF total
```

This gives a calculated resonance range of approximately:

```text
75.8 ... 79.2 kHz
```

The worst calculated offset from 77.5 kHz is therefore about 1.7 kHz.

With the 330 kOhm damping resistor, the narrowest expected loaded bandwidth is still around 3.7 kHz total, or about ±1.85 kHz around resonance. Thus 77.5 kHz remains inside the approximate -3 dB region without per-board trimming.

This is the core reason for accepting some resonant gain loss: production repeatability and PM bandwidth are more valuable than chasing the maximum possible Q on a tiny integrated ferrite.

## Input buffer selection

Preferred Rev.0 buffer:

```text
Texas Instruments OPA810IDBVR
SOT-23-5
FET input
RRIO
active product
5 V operation
```

Relevant properties:

```text
common-mode input impedance ~= 12 GOhm || 2 pF
open-loop differential input capacitance ~= 0.5 pF typ
input bias current pA class
140 MHz small-signal bandwidth
```

The OPA810 replaces the historically unidentified BF245A bias network for the integrated-antenna build.

The principal reason is not bandwidth; 77.5 kHz is trivial for this amplifier. The reason is **predictable high input impedance with low, published input capacitance**, which makes a fixed antenna tuning network practical.

The OPA810 is also currently well stocked at major distributors.

## Biasing topology

Run the OPA810 from `5V_AFE` and center the antenna network around a quiet 2.5 V analog bias:

```text
5V_AFE
  |
  10k
  +---- VCM_AFE ~= 2.5 V
  10k
  |
 GND

VCM_AFE -> 10 uF || 1 uF || 100 nF to ground
```

Antenna/input topology:

```text
                    CANT1 560p C0G
               +----||----+
               |          |
VCM_AFE -------+-- ANT_X --+------ ANT_IN ------> OPA810 +IN
               |          |                       follower
               +-- 22p ---+
               |          |
               +--330k----+

OPA810 -IN <---------------- OPA810 OUT
```

The drawing is conceptual: the coil and the fixed capacitors/resistor are all placed as one compact parallel resonant network between `ANT_IN` and the low-AC-impedance `VCM_AFE` node.

The OPA810 output then feeds the LTC1562 input stage using the final filter interface defined in the AFE schematic.

## Layout rules

The antenna block is a hard placement constraint for Quilter.

Rules:

- place the B82453C0275A000 at the board edge farthest from ECP5, USB, Raspberry Pi and switching regulators;
- orient the X magnetic axis according to the TDK package axis drawing and record that orientation in silkscreen/documentation;
- keep `ANT_IN` copper extremely short;
- place 560 pF, 22 pF and 330 kOhm immediately beside the antenna pads;
- place OPA810 immediately beside `ANT_IN`;
- no ground/power switching-current trace under the antenna/input cluster;
- no FPGA clock, ADC SCK, SPI, USB or buck switch node beneath or adjacent to the ferrite;
- avoid large copper pours directly under the ferrite unless later electromagnetic analysis specifically justifies them;
- unused Y/Z winding pads remain electrically open and have no long traces.

The HAT+ variant needs the strictest keepout because the Raspberry Pi is a strong local interference source.

## External-antenna option

The integrated TDK antenna is the reference Rev.0 configuration.

A large external ferrite connector may still be provided for sensitivity experiments, but it is **not** part of the fixed reference receive path and must not add capacitance to `ANT_IN` when unused.

Use a true isolation option such as a normally unpopulated link/0-ohm selector rather than permanently hanging a connector stub on the tuned node.

## No-trim policy

Reference BOM:

```text
ANT1   TDK B82453C0275A000, X winding
CANT1  560 pF C0G/NP0 1%
CANT2   22 pF C0G/NP0 1%
RANT   330 kOhm thin-film 1%
U_BUF  OPA810IDBVR
```

There is no trimmer and no instruction to measure each antenna and substitute capacitors.

Prototype characterization will still verify that the resulting production design behaves as predicted, but those measurements are **validation**, not a per-unit tuning procedure and not an input to choosing the reference R/C values.

## Sources

- TDK B82453C0275A000 product data / B82453C family data sheet.
- Texas Instruments OPA810 product page and data sheet.
- PTB DCF77 phase-modulation documentation.
- Distributor availability snapshots, September 2026; stock must be rechecked at BOM release.
