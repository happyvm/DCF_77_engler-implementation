# Rev.0 power-tree architecture

## Decision

Both PCB variants share the same internal power architecture after a common `5V_SYS` boundary.

```text
HAT+ 5 V ------------------+
                           +--> 5V_SYS
USB-C 5 V sink ------------+

5V_SYS
  |
  +--> quiet direct AFE feed -> 5V_AFE
  |
  +--> LT3042 -> 3V3_ADC_A
  |
  +--> TPS7A20 -> 3V3_CLK
  |
  +--> TPS628502 -> 3V3_D
  |                    |
  |                    +--> ECP5 VCCIO8 / configuration flash / digital I/O
  |                    +--> TPS7A20 -> 2V5_AUX
  |
  +--> TPS628502 -> 1V1_CORE
```

The guiding principle is simple:

> switching conversion is allowed in the digital partition, but the ferrite/AFE/ADC/clock paths must not depend directly on a noisy switching rail.

This is a reconstruction choice, not recovered Engeler power circuitry.

## Why there is no boost converter for the 5 V analog rail

The historical LTC1562 is still in production and its specified total supply range starts at **4.75 V**. Its current is roughly 17–20 mA typical near the low end of the supply range, with the data sheet specifying up to about 23.5 mA over temperature in the ±2.375 V test condition.

Therefore a nominal 5 V system source can power it directly without an additional regulator if the path has very low DC drop.

Rev.0 intentionally avoids:

```text
5V_SYS -> boost -> 5.5/6 V -> LDO -> 5.0 V AFE
```

because adding a switcher solely to create headroom for a linear 5 V rail creates exactly the sort of deterministic interference source this receiver is trying to avoid.

Instead:

```text
5V_SYS
  -> low-R protection / current-measure option
  -> damped passive filtering
  -> 5V_AFE
```

The board must monitor or at least expose `5V_AFE` at a test point. If the supply falls too close to the LTC1562 4.75 V minimum, receiver performance is no longer guaranteed and an `AFE_POWER_GOOD` diagnostic should indicate this condition.

This is particularly important for the HAT+ variant because the receiver cannot assume unlimited voltage margin on a remotely supplied 5 V rail.

## 5V_AFE passive filter

Do not choose a ferrite bead solely from its "600 ohm at 100 MHz" headline number; that says little about rejection around 77.5 kHz.

The first PCB should provide configurable pads for a **damped low-frequency supply filter**, for example:

```text
5V_SYS ---- R/FILTER ----+---- 5V_AFE
                         |
                        Cbulk
                         |
                        AGND
```

Starting experimental population:

```text
series element   0R / 0.22R / 0.47R selectable
Cbulk            47 uF to 100 uF low-ESR
Cmid             1 uF ceramic
Chf              100 nF ceramic
```

The series element and bulk capacitance must be selected from measured conducted-noise data, because excessive series resistance reduces the already-small 5 V voltage margin.

Provide a footprint option for a shielded inductor/ferrite only if measurements show a benefit. Do not freeze an undamped LC resonance into Rev.0 merely to make the schematic look more filtered.

## Loads on 5V_AFE

Initial direct-analog loads are:

```text
LTC1562     ~20 mA class
LTC6912     ~4 mA typical total at 5 V, gain = 1
input stage TBD
```

The ADC driver is no longer planned on this rail. Moving the driver to `3V3_ADC_A` materially reduces the dependency of ADC performance on raw 5 V quality.

Budget the first hardware for at least **75 mA continuous 5V_AFE capacity** so experimental front-end changes do not require a power-tree redesign.

## 3V3_ADC_A — precision ADC/driver rail

Preferred regulator:

```text
LT3042EMSE#PBF or equivalent package/grade
5V_SYS -> 3.3 V
200 mA capability
```

ADI currently marks LT3042 **recommended for new designs**. Its relevant properties include approximately:

```text
noise       0.8 uVrms, 10 Hz to 100 kHz
PSRR        79 dB at 1 MHz
Iout        200 mA
Vin         1.8 V to 20 V
```

Digi-Key showed several thousand units of the MSOP-EP model in stock in the September 2026 snapshot.

This rail powers:

```text
LTC1407A-1 ADC
OPA2835 ADC driver
VCM_ADC bias network/buffer if later added
```

The LTC1407A family draws roughly 4.7 mA active at its maximum rated sampling condition, so the LT3042 has enormous current margin for the complete ADC island.

Keep the LT3042, ADC and driver physically together at the analog/digital boundary.

## ADC driver change: OPA2835

Rev.0 now prefers the **OPA2835** over the earlier OPA2810 candidate.

Reason:

- OPA2810 requires at least 4.75 V, tying ADC-driver operation to the raw 5 V margin;
- OPA2835 operates from 2.5 V to 5.5 V;
- it is dual-channel;
- it is intended for low-power signal conditioning and SAR/ADC drive applications;
- it has approximately 56 MHz small-signal bandwidth and about 160 V/us slew rate;
- typical quiescent current is only about 250 uA per channel;
- Digi-Key showed roughly 2700 units of the VSSOP `OPA2835IDGSR` in stock in September 2026.

Run it from `3V3_ADC_A`.

The exact settling/noise result with the LTC1407A input network must still be verified on hardware before production release.

## 3V3_CLK — separate low-noise clock rail

Do not place the TCXO on the ADC LDO output just because both may use 3.3 V.

Clock output edges produce dynamic current that should not share the final precision regulator/return path with the ADC.

Preferred clock-rail regulator class:

```text
TPS7A20, fixed 3.3 V option
```

TI currently lists TPS7A20 as active. Key figures are approximately:

```text
Iout       300 mA
noise      7 uVrms
PSRR       60 dB at 100 kHz
Iq         6.5 uA typical
Vin        1.6 V to 6 V
```

This is more than adequate for a low-current TCXO while providing isolation from `5V_SYS`.

Final TCXO OPN remains open and must still be selected from actual distributor stock.

## 3V3_D — main FPGA/configuration I/O rail

Preferred converter candidate:

```text
TPS628502DRLR
2 A synchronous buck
adjustable output
5V_SYS -> 3.3 V
```

TI marks TPS628502 active. Digi-Key showed roughly ten thousand standard devices in stock in the September 2026 snapshot.

Advantages for Rev.0:

- 2 A gives comfortable transient margin;
- 2.7–6 V input range suits 5V_SYS;
- programmable switching frequency;
- forced-PWM capability;
- spread-spectrum option;
- power-good output;
- pre-bias startup support.

This rail powers the ECP5 3.3 V I/O banks selected for 3.3 V operation, configuration flash, slow digital support and possibly the LCD logic.

Keep the entire buck hot loop in the digital/power region and physically far from the ferrite and first analog stage.

## 1V1_CORE — ECP5 core

Use another TPS628502 configured to **1.1 V** for the ECP5 `VCC` rail.

Using the same converter for 3.3 V and 1.1 V:

- reduces BOM diversity;
- gives 2 A margin without first needing an exact final RTL power estimate;
- provides independent EN/PG control;
- keeps the reference board safe during lab-debug builds, even though release RTL is constrained to the XC3S1400AN resource envelope.

The final production current requirement must be calculated with Lattice's ECP5 power estimator using the real clock rates, utilization and I/O toggling before the PCB is released.

Do not treat 2 A as an expected normal load; it is regulator capability/headroom.

## 2V5_AUX — ECP5 auxiliary rail

Generate ECP5 `VCCAUX = 2.5 V` from `3V3_D` with a low-current LDO.

Preferred class:

```text
TPS7A20 fixed 2.5 V
3V3_D -> 2V5_AUX
```

This avoids a third switcher and gives a quiet, simple auxiliary rail with ample 300 mA capability.

The exact ECP5 auxiliary current must still be confirmed using the selected device/package and Lattice power estimation.

## ECP5 power sequencing

The plain `LFE5U` power rails of interest are:

```text
VCC       1.1 V
VCCAUX    2.5 V
VCCIO8    selected as 3.3 V for configuration interface
other VCCIO according to bank use
```

Lattice monitors `VCC`, `VCCAUX` and `VCCIO8` during power-up. For Master-SPI configuration, `VCCIO8` must be high enough for the external SPI flash interface before configuration begins, or configuration must be held off.

Rev.0 should therefore make `3V3_D` the **first controlled digital rail**:

```text
5V_SYS
  |
  +--> 3V3_D buck
         |
         +--> VCCIO8 + SPI flash
         |
         +--> PG_3V3_D
                 |
                 +--> enable 1V1_CORE
                 +--> enable 2V5_AUX
```

In addition, route `PROGRAMN` so it can be held low by reset/supervisor logic until the digital rails are valid. Do not rely on uncontrolled converter ramp ordering.

The ECP5 data sheet requires monotonic supply ramps and documents POR thresholds around 0.9 V for `VCC`, 2.0 V for `VCCAUX`, and 0.95 V for `VCCIO8`.

## LCD power

The transflective 20x2 LCD remains common to both boards.

Preferred policy:

```text
LCD logic     -> 3V3_D
backlight     -> switched separately
```

Do not PWM the backlight continuously during precision receive measurements unless EMI testing demonstrates that it is harmless.

Preferred modes:

```text
RF/precision mode: backlight off
user mode:         backlight DC on
```

If brightness control is wanted later, use a low-rate or carefully selected scheme only after measuring antenna-spectrum impact.

## Power-tree testability

Rev.0 must expose or permit measurement of:

```text
TP_5V_SYS
TP_5V_AFE
TP_3V3_ADC_A
TP_3V3_CLK
TP_3V3_D
TP_2V5_AUX
TP_1V1_CORE
```

Also provide current-measure/0-ohm links for at least:

```text
5V_AFE
3V3_ADC_A
1V1_CORE
```

These links are valuable when correlating digital activity with 77.5 kHz self-interference.

## Ground/placement policy

Do not create disconnected "analog ground" and "digital ground" islands joined by a random thin trace.

Use a continuous ground reference while controlling **current paths by placement**:

```text
ferrite/input -> AFE -> PGA -> ADC | ECP5 -> USB/Pi/power
                quiet direction     | noisy direction
```

Rules:

- switcher hot loops stay in the digital/power region;
- no switch node trace runs under the AFE;
- ADC driver/LDO/ADC form one tight island at the analog/digital boundary;
- the TCXO has its own local LDO and return geometry;
- incoming 5 V power reaches digital converters without first flowing through the AFE region;
- AFE receives a branch from the 5 V entry point through its own passive filter;
- bulk digital return currents must not pass beneath the ferrite/input stage.

These constraints must be encoded before Quilter placement/routing.

## Preliminary power budget

This is intentionally conservative and not a prediction of final consumption.

| Rail | Design capacity | Expected major loads |
|---|---:|---|
| `5V_AFE` | >=75 mA | LTC1562, LTC6912, input stage |
| `3V3_ADC_A` | 200 mA | LTC1407A-1, OPA2835, ADC bias |
| `3V3_CLK` | 300 mA regulator capability | TCXO only / small timing support |
| `3V3_D` | 2 A | ECP5 I/O, flash, LCD logic, digital support |
| `2V5_AUX` | 300 mA | ECP5 VCCAUX |
| `1V1_CORE` | 2 A | ECP5 VCC |

The actual board input budget must be recalculated after:

1. exact ECP5 OPN/package is frozen;
2. actual RTL synthesis/activity is available;
3. LCD/backlight is selected;
4. TCXO OPN is selected;
5. USB bridge/debug hardware is selected.

## Validation before schematic freeze

1. Power the analog path from a clean bench 5 V supply and establish the baseline 77.5 kHz noise floor.
2. Enable `3V3_D` and `1V1_CORE` switchers and measure added antenna spur/noise.
3. Compare forced-PWM versus spread-spectrum converter modes.
4. Verify no beat products land at or near 77.5 kHz or the PM bandwidth.
5. Validate the direct `5V_AFE` rail at minimum realistic `5V_SYS` voltage and maximum analog load.
6. Measure ADC code noise using the LT3042 rail with the FPGA idle and active.
7. Measure TCXO phase/noise impact with its independent TPS7A20 rail.
8. Verify power-up/down repeatedly while checking ECP5 configuration reliability.
9. Validate HAT+ standby behavior and absence of GPIO back-powering.
10. Validate USB-C attach/inrush behavior on the standalone board.

## Current Rev.0 power BOM candidates

| Function | Candidate | Status |
|---|---|---|
| 1.1 V ECP5 core | TPS628502DRLR | active, stocked candidate |
| 3.3 V digital | TPS628502DRLR | active, stocked candidate |
| 2.5 V auxiliary | TPS7A20 fixed 2.5 V | active candidate |
| 3.3 V ADC analog | LT3042 | recommended-for-new-designs candidate |
| 3.3 V TCXO | TPS7A20 fixed 3.3 V | active candidate |
| 5 V AFE | direct low-loss filtered `5V_SYS` | architecture choice |

Exact passive values, package suffixes and approved alternate OPNs remain to be frozen from schematic simulation, layout constraints and distributor checks.

## Sources

- Lattice ECP5/ECP5-5G family data sheet and hardware checklist.
- Analog Devices LTC1562 data sheet/product page.
- Analog Devices LTC6912 data sheet/product page.
- Analog Devices LTC1407A/LTC1407A-1 documentation.
- Analog Devices LT3042 product documentation.
- Texas Instruments TPS628502 documentation.
- Texas Instruments TPS7A20 documentation.
- Texas Instruments OPA2835 documentation.
- September 2026 Digi-Key inventory observations, treated as dated sourcing snapshots only.
