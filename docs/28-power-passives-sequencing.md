# Rev.0 fixed power passives, switching policy and sequencing

## Decision

Rev.0 now freezes the electrical values of the receiver power tree. The reference PCB must not require choosing regulator passives experimentally or selecting a different supply-filter resistor after bring-up.

The only remaining power work before fabrication is ordinary verification: PDN review, ECP5 power estimation with real RTL activity, thermal review and measurement of conducted/radiated self-interference.

Reference rails:

```text
5V_SYS
  |
  +--> 0.10 ohm + fixed RC bypass -> 5V_AFE
  |
  +--> LT3042EMSE#PBF -> 3V3_ADC_A
  |
  +--> TPS7A2033PDQNR -> 3V3_CLK
  |
  +--> TPS628502DRLR -> 1V1_CORE

standalone only:
5V_SYS -> TPS628502DRLR -> 3V3_D

HAT+ only:
PI_3V3 -> current-measure link -> 3V3_D

both variants:
3V3_D -> TPS7A2025PDQNR -> 2V5_AUX
```

The HAT+ 5 V path is switched by `TPS22975NDSGR`; the standalone 5 V path remains the USB-C/eFuse path defined in `docs/25-standalone-usbc-power.md`.

## 1. Fixed 5V_AFE filter

Do not use a ferrite bead or selectable series resistor as the reference population. The AFE supply must remain low-drop and deterministic because the LTC1562 minimum total supply is close to the nominal 5 V input.

Reference network:

```text
5V_SYS
   |
R_AFE = 0.10 ohm, 1%, 0805
   |
   +--------- 5V_AFE
   |
   +-- 100 uF / >=10 V low-ESR bulk -> GND
   +--   1 uF / >=10 V X7R       -> GND
   +-- 100 nF / >=10 V X7R       -> GND
```

At the design-budget load of 75 mA:

```text
DC drop = 0.10 ohm * 0.075 A
        = 7.5 mV
```

The ideal 0.10 ohm / 100 uF pole is about 15.9 Hz. Real high-frequency rejection is limited by capacitor ESR/ESL and layout, but the network is intentionally damped and has no LC resonance to tune.

A test point remains on `5V_AFE`, but prototype measurements validate the fixed design rather than determine a production resistor value.

## 2. TPS628502 common implementation

Exact converter:

```text
TPS628502DRLR
2 A synchronous buck
SOT583 / DRL
```

The same implementation is used for:

```text
U_CORE  : 5V_SYS -> 1V1_CORE
U_3V3_D : 5V_SYS -> 3V3_D    [standalone only]
```

### Why Rev.0 does not use the default 2.25 MHz setting

The TPS628502 permits 1.8 to 4 MHz operation and supports forced PWM.

The internally fixed 2.25 MHz nominal setting is undesirable for this receiver because:

```text
29 * 77.5 kHz = 2.2475 MHz
```

so the default nominal switcher is only 2.5 kHz away from the 29th harmonic of the wanted DCF77 carrier.

This does not prove that a 2.25 MHz converter would corrupt reception, but there is no reason to choose that deterministic relationship when the converter gives us frequency control.

### Fixed switching configuration

Reference population:

```text
COMP/FSET -> 5.76 kOhm, 1%, to GND
MODE/SYNC -> logic high through 10 kOhm
SSC       -> disabled
mode      -> forced PWM
nominal fsw ~= 3.125 MHz
```

For compensation setting 1 with SSC disabled, the manufacturer range is 1.8 MHz at 10 kOhm to 4 MHz at 4.5 kOhm. `5.76 kOhm` therefore places the nominal frequency at approximately 3.125 MHz.

Forced PWM is deliberate. Do not use automatic PWM/PFM in the reference receiver because light-load PFM creates lower-frequency burst structure that is more difficult to characterize around a weak LF radio front end.

Spread-spectrum modulation is also disabled in the reference build. A deterministic narrow switching spectrum is easier to locate, contain and correlate against the ferrite spectrum than a deliberately spread switching source.

The oscillator tolerance of the converter means 3.125 MHz is not a precision spectral notch. The objective is to avoid the particularly unattractive default nominal relationship and PFM burst behavior, not to claim mathematically guaranteed harmonic avoidance.

### Inductor

Reference part:

```text
Murata DFE252012PD-R47M=P2
0.47 uH
shielded power inductor
2.5 x 2.0 x 1.2 mm class
```

The TPS628502 data sheet explicitly lists the `DFE252012PD-R47M` family as a typical 0.47 uH inductor for the 2 A device.

Use the same inductor on `1V1_CORE` and standalone `3V3_D` to reduce BOM diversity.

### Input/output capacitors

Per buck:

```text
CIN  = 10 uF, X7R, >=10 V, 1206 preferred
       + 100 nF X7R close to VIN/GND

COUT = 2 x 10 uF, X7R, >=6.3 V, 1206 preferred
```

The two output capacitors intentionally provide DC-bias margin above the TPS628502 compensation-setting-1 minimum effective capacitance.

Do not substitute tiny high-capacitance packages without checking effective capacitance at the applied DC voltage.

## 3. 1V1_CORE feedback

Reference divider:

```text
R_TOP = 39.2 kOhm, 0.1%
R_BOT = 47.0 kOhm, 0.1%
C_FF  = 10 pF C0G/NP0
```

Using the nominal 0.6 V feedback reference:

```text
VOUT ~= 0.6 * (1 + 39.2 / 47.0)
     ~= 1.100 V
```

This rail feeds the ECP5 `VCC` balls only.

## 4. Standalone 3V3_D feedback

Reference divider:

```text
R_TOP = 88.7 kOhm, 0.1%
R_BOT = 19.6 kOhm, 0.1%
C_FF  = 10 pF C0G/NP0
```

Nominal result:

```text
VOUT ~= 3.316 V
```

This is inside the operating range of ECP5 3.3 V banks and the W25Q64JV.

The HAT+ does not populate this converter; its `3V3_D` is supplied by the Raspberry Pi `PI_3V3` rail.

## 5. 3V3_ADC_A — LT3042

Exact regulator:

```text
LT3042EMSE#PBF
200 mA
10-MSOP exposed pad
```

Reference passives:

```text
RSET = 33.2 kOhm, 0.1% thin film
CSET = 4.7 uF X7R
CIN  = 10 uF X7R, >=10 V
COUT = 10 uF X7R, >=6.3 V
       + local 100 nF at ADC/driver loads
```

The LT3042 requires at least 4.7 uF low-ESR output capacitance for stability; 10 uF is selected to provide practical transient and DC-bias margin.

`3V3_ADC_A` powers only the LTC1407A-1, OPA2835 and their ADC-bias island. It is not reused for FPGA I/O or the TCXO.

The ILIM pin is not used to create a low custom current limit in Rev.0. Keep the manufacturer's normal current-capability configuration and rely on upstream source protection; the ADC island is already a small load and a tight artificial current limit could make startup behavior less robust.

## 6. 3V3_CLK — TPS7A20

Exact regulator:

```text
TPS7A2033PDQNR
fixed 3.3 V
300 mA
1 x 1 mm X2SON
```

Reference bypass:

```text
CIN  = 2.2 uF X7R, >=10 V
COUT = 2.2 uF X7R, >=6.3 V
       + 100 nF immediately at SiT5356 supply
```

The manufacturer minimum load capacitance is 1 uF; 2.2 uF gives ordinary DC-bias/temperature margin without creating a large shared energy reservoir.

This rail powers the `SiT5356AI-FQ-33E0-25.000000` TCXO only, plus any tiny local clock-support load explicitly added later.

## 7. 2V5_AUX — TPS7A20

Exact regulator:

```text
TPS7A2025PDQNR
fixed 2.5 V
300 mA
1 x 1 mm X2SON
```

Reference bypass:

```text
CIN  = 2.2 uF X7R, >=6.3 V
COUT = 2.2 uF X7R, >=6.3 V
```

Input is `3V3_D` on both PCB variants.

This rail powers ECP5 `VCCAUX` only unless a later pin-accurate review identifies another legitimate 2.5 V auxiliary load.

## 8. HAT+ 5 V switch

Exact HAT load switch:

```text
TPS22975NDSGR
6 A capability
~16 mOhm typical RON
adjustable rise time
no quick-output-discharge resistor on N variant
```

Reference wiring:

```text
PI_5V -> VIN/VBIAS
PI_3V3 -> ON
ON -> 100 kOhm -> GND
CT -> 1.0 nF, >=30 V -> GND
VOUT -> 5V_SYS
```

At 5 V, the manufacturer typical table gives approximately 1.75 ms 10%-90% rise time with 1 nF on CT.

The low RON is important because `5V_AFE` has little permissible voltage-drop budget.

The `100 kOhm` ON pulldown guarantees the switch is off when Pi 3.3 V disappears in HAT+ STANDBY.

## 9. Sequencing — standalone USB-C

Reference order:

```text
USB-C/eFuse
    |
    v
5V_SYS
    |
    +--> U_3V3_D starts
    |       |
    |       +--> VCCIO8 + W25Q64 + all VCCIO
    |       +--> TPS7A2025 -> 2V5_AUX
    |       +--> PG_3V3_D
    |              |
    |              +--> enable U_CORE -> 1V1_CORE
    |
    +--> LT3042 -> 3V3_ADC_A
    +--> TPS7A2033 -> 3V3_CLK
    +--> fixed 5V_AFE branch
```

Thus VCCIO8 is established before the ECP5 core rail is enabled.

`PG_3V3_D` is the reference core-enable signal. Pull it up to `3V3_D` as required by the TPS628502 open-drain power-good output.

## 10. Sequencing — Raspberry Pi HAT+

Reference order:

```text
Pi active
   |
   +--> PI_3V3 appears
   |       |
   |       +--> 3V3_D / VCCIO8 / W25Q64
   |       +--> TPS7A2025 -> 2V5_AUX
   |       +--> TPS22975N ON
   |
   +--> PI_5V already present
           |
           +--> TPS22975N controlled rise -> 5V_SYS
                    |
                    +--> U_CORE -> 1V1_CORE
                    +--> 3V3_ADC_A
                    +--> 3V3_CLK
                    +--> 5V_AFE
```

When `PI_3V3` disappears in STANDBY, the load switch turns off and every locally generated receiver rail collapses; no alternate source is allowed to back-power `3V3_D`.

## 11. ECP5 POR / PROGRAMN policy

Rev.0 does not add a separate analog sequencing supervisor solely to hold `PROGRAMN` low.

Lattice's on-chip POR monitors `VCC`, `VCCAUX` and `VCCIO8`; initialization waits for all three monitored rails to pass their thresholds. The ECP5 data sheet additionally requires VCCIO8 to reach the SPI-flash input-high requirement before at least one of VCC/VCCAUX reaches its POR threshold when Master SPI is used.

The two reference sequences above intentionally satisfy that ordering by making the 3.3 V configuration domain first.

Therefore:

```text
PROGRAMN -> normal 4.7 kOhm pull-up to VCCIO8
          -> manual/test access
          -> optional open-drain host reset only
```

A fixed arbitrary delay is not used as a substitute for ECP5 POR.

## 12. ECP5 fixed decoupling baseline

The exact BG256 power-ball map is already frozen in `docs/27-ecp5-pin-plan-hat.md`.

Reference local decoupling:

### `1V1_CORE`

```text
6 x 100 nF X7R, one associated with each VCC ball
2 x 10 uF X7R bulk close to FPGA core-power region
```

### `2V5_AUX`

```text
2 x 100 nF X7R, one per VCCAUX ball
1 x 4.7 uF X7R local bulk
```

### each populated `3V3_D` VCCIO bank

```text
100 nF X7R per VCCIO supply ball
1 uF X7R local per bank
```

Additional digital bulk:

```text
10 uF X7R near Bank 8 / W25Q64 configuration cluster
10 uF X7R near the main 3V3_D entry to ECP5
```

These are fixed reference values. PDN measurement may prove the design good or identify a board-revision issue, but production boards do not receive individually tuned decoupling values.

## 13. Placement rules

The two TPS628502 hot loops are hard-constrained to the digital/power side of the board.

For the HAT+, only the 1.1 V buck exists locally. For standalone, the 1.1 V and 3.3 V bucks form one compact power region.

Rules:

- `SW` copper is the minimum practical area;
- inductor immediately adjacent to `SW` and output capacitors;
- VIN capacitor immediately adjacent to VIN/GND;
- no switch node, inductor or FSET trace under/near ferrite, OPA810, LTC1562 or TCXO;
- COMP/FSET resistor placed immediately at the pin;
- MODE/SYNC pull-up local to the converter;
- LT3042 remains physically inside the ADC island;
- TPS7A2033 remains beside the TCXO;
- the 5V_AFE 0.10-ohm resistor and bulk capacitor sit at the branch entrance, not at the far end of an analog trace.

## 14. Validation is not tuning

Prototype acceptance still includes:

1. check all rail voltages/ramp order;
2. measure buck spectra at ferrite input;
3. verify no persistent spur corrupts the 77.5 kHz carrier/PM band;
4. check ADC-code noise with digital loads idle/active;
5. check TCXO phase behavior;
6. check `5V_AFE` minimum voltage under HAT and USB worst-case load;
7. run ECP5 power estimate and verify regulator/inductor thermal margin;
8. repeat boot cycles and HAT STANDBY cycles.

A failed validation causes a board revision, not per-unit resistor/capacitor selection.

## Reference BOM subset

| Function | Reference part/value |
|---|---|
| core buck | `TPS628502DRLR` |
| standalone 3.3 V buck | `TPS628502DRLR` |
| buck inductor | `DFE252012PD-R47M=P2`, 0.47 uH |
| buck FSET | 5.76 kOhm 1%, SSC off |
| buck mode | forced PWM |
| core divider | 39.2 k / 47.0 k / 10 pF |
| 3.3 V divider | 88.7 k / 19.6 k / 10 pF |
| ADC LDO | `LT3042EMSE#PBF` |
| ADC LDO RSET | 33.2 kOhm |
| ADC LDO CSET | 4.7 uF |
| clock LDO | `TPS7A2033PDQNR` |
| auxiliary LDO | `TPS7A2025PDQNR` |
| HAT 5 V switch | `TPS22975NDSGR`, CT=1 nF |
| AFE series filter | 0.10 ohm 1% |
| AFE bulk | 100 uF + 1 uF + 100 nF |

## Sources

- TI TPS628501/TPS628502/TPS628503 data sheet, Rev. C.
- TI TPS7A20 data sheet, current revision.
- TI TPS22975/TPS22975N data sheet.
- Analog Devices LT3042 data sheet, current revision.
- Lattice ECP5/ECP5-5G Family Data Sheet.
- Lattice ECP5/ECP5-5G Hardware Checklist.
- Murata DFE252012PD inductor documentation.
