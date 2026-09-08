# Rev.0 power-tree architecture

## Decision

Rev.0 power architecture is now frozen at the electrical-value level.

The two PCB variants use the same receiver rails, but `3V3_D` intentionally has a different source:

```text
Standalone USB-C:
5V_SYS -> TPS628502 -> 3V3_D

Raspberry Pi HAT+:
PI_3V3 ------------> 3V3_D
```

All precision/analog rails remain locally generated on both boards.

The exact regulator passives, switcher mode/frequency, HAT load switch and ECP5 decoupling baseline are defined in:

- [`28-power-passives-sequencing.md`](28-power-passives-sequencing.md)
- [`../hardware/tscircuit/power-plan.json`](../hardware/tscircuit/power-plan.json)

## Common rail architecture

```text
                         5V_SYS
                           |
       +-------------------+-------------------+
       |                   |                   |
       v                   v                   v
 fixed 0.10R RC       LT3042EMSE         TPS7A2033
       |                   |                   |
    5V_AFE             3V3_ADC_A            3V3_CLK
       |                   |                   |
 OPA810/LTC1562      LTC1407A/OPA2835        SiT5356
 /LTC6912
                           
5V_SYS -> TPS628502 -> 1V1_CORE -> ECP5 VCC

3V3_D  -> TPS7A2025 -> 2V5_AUX  -> ECP5 VCCAUX
```

Digital 3.3 V:

```text
Standalone:
5V_SYS -> TPS628502 -> 3V3_D

HAT+:
PI_3V3 -> current-measure/0R link -> 3V3_D
```

`3V3_D` powers ECP5 VCCIO banks, VCCIO8, W25Q64, LCD logic and digital host/PPS support. On HAT+ it also powers the HAT ID EEPROM.

## Fixed 5V_AFE branch

The historical LTC1562 requires a supply close to 5 V, so Rev.0 deliberately avoids a boost/LDO chain and avoids a ferrite-bead filter whose useful impedance at 77.5 kHz is poorly represented by its 100 MHz headline specification.

Reference branch:

```text
5V_SYS
  -> 0.10 ohm, 1%, 0805
  -> 5V_AFE
       -> 100 uF low-ESR
       -> 1 uF X7R
       -> 100 nF X7R
```

At the conservative 75 mA AFE design budget, the resistor drops only about 7.5 mV.

There is no reference-BOM `0R/0.22R/0.47R` selection anymore. Prototype measurements validate this fixed network rather than select a production value.

## 3V3_ADC_A

Exact regulator:

```text
LT3042EMSE#PBF
```

Reference programming/bypass:

```text
RSET = 33.2 kOhm, 0.1%
CSET = 4.7 uF
CIN  = 10 uF X7R
COUT = 10 uF X7R
```

Loads:

```text
LTC1407AIMSE-1#PBF
OPA2835IDGSR
ADC common-mode/bias island
```

The LT3042 is not shared with the TCXO or FPGA digital loads.

## 3V3_CLK

Exact regulator:

```text
TPS7A2033PDQNR
fixed 3.3 V
```

Reference bypass:

```text
CIN  = 2.2 uF X7R
COUT = 2.2 uF X7R
100 nF directly at SiT5356 supply
```

This rail is dedicated to the fixed `SiT5356AI-FQ-33E0-25.000000` 25 MHz TCXO.

## 2V5_AUX

Exact regulator:

```text
TPS7A2025PDQNR
fixed 2.5 V
```

Input:

```text
3V3_D
```

Reference bypass:

```text
CIN  = 2.2 uF X7R
COUT = 2.2 uF X7R
```

Load is ECP5 `VCCAUX`.

## TPS628502 policy

Exact buck:

```text
TPS628502DRLR
```

Used for:

```text
1V1_CORE              both boards
3V3_D                  standalone only
```

Reference common power stage:

```text
L = Murata DFE252012PD-R47M=P2, 0.47 uH
CIN = 10 uF + 100 nF
COUT = 2 x 10 uF X7R
```

Reference operating mode:

```text
COMP/FSET = 5.76 kOhm to GND
nominal fsw ~= 3.125 MHz
SSC = OFF
MODE/SYNC = HIGH
mode = forced PWM
```

The default internal 2.25 MHz setting is intentionally not used because:

```text
29 * 77.5 kHz = 2.2475 MHz
```

Putting the nominal converter only 2.5 kHz from that carrier harmonic provides no useful benefit. Forced PWM also avoids light-load PFM burst behavior. The converter frequency tolerance means this is an EMI-risk reduction choice, not a guaranteed spectral notch.

### 1V1_CORE feedback

```text
R_TOP = 39.2 kOhm 0.1%
R_BOT = 47.0 kOhm 0.1%
C_FF  = 10 pF C0G
VOUT ~= 1.100 V
```

### standalone 3V3_D feedback

```text
R_TOP = 88.7 kOhm 0.1%
R_BOT = 19.6 kOhm 0.1%
C_FF  = 10 pF C0G
VOUT ~= 3.316 V
```

## HAT+ input power

The HAT uses both Pi supply rails:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure link -> 3V3_D
```

Reference load-switch settings:

```text
TPS22975NDSGR
VIN/VBIAS = PI_5V
ON        = PI_3V3
ON pulldown = 100 kOhm
CT        = 1.0 nF, >=30 V
```

At 5 V, 1 nF CT gives approximately 1.75 ms typical output rise time according to the manufacturer's table.

The low switch resistance preserves the already-small LTC1562 voltage margin.

When `PI_3V3` disappears in HAT+ STANDBY, the switch is forced off and the receiver's locally generated rails disappear. No alternate source is allowed to back-power `3V3_D`.

See [`26-hat-power.md`](26-hat-power.md).

## Standalone USB-C input power

The standalone shell remains:

```text
USB4105-GF-A
   -> TUSB320LAIRWBR UFP/sink
   -> TPS259470ARPWR eFuse
   -> 5V_SYS
```

No USB-PD is required for Rev.0.

See [`25-standalone-usbc-power.md`](25-standalone-usbc-power.md).

## ECP5 sequencing

Lattice monitors `VCC`, `VCCAUX` and `VCCIO8` with internal POR. For Master SPI, VCCIO8 must be high enough for the external SPI flash before the relevant core/auxiliary threshold sequence can launch configuration correctly.

Rev.0 therefore establishes the 3.3 V configuration domain before the core rail.

### Standalone

```text
5V_SYS
   -> 3V3_D
        -> VCCIO8 / W25Q64
        -> 2V5_AUX
        -> PG_3V3_D
             -> enable 1V1_CORE
```

### HAT+

```text
PI_3V3
   -> 3V3_D / VCCIO8 / W25Q64
   -> 2V5_AUX
   -> enable TPS22975N
        -> 5V_SYS
             -> 1V1_CORE
```

The reference design relies on the ECP5 internal POR plus this deterministic supply ordering. It does not add a separate arbitrary-delay supervisor solely for `PROGRAMN`.

`PROGRAMN` retains its normal pull-up, test access and optional open-drain reset path.

## ECP5 decoupling baseline

Using the frozen BG256 power-ball map:

```text
1V1_CORE:
  6 x 100 nF local
  2 x 10 uF bulk near core region

2V5_AUX:
  2 x 100 nF local
  1 x 4.7 uF bulk

3V3_D / VCCIO:
  100 nF per VCCIO supply ball
  1 uF per populated bank
  10 uF near Bank 8 / W25Q64
  10 uF at main ECP5 3V3_D entry
```

These values are fixed for Rev.0. A PDN problem found during validation causes a board revision, not per-unit capacitor selection.

## Testability

Expose:

```text
TP_5V_SYS
TP_5V_AFE
TP_3V3_ADC_A
TP_3V3_CLK
TP_3V3_D
TP_2V5_AUX
TP_1V1_CORE
```

Provide current-measure/0-ohm links for at least:

```text
5V_AFE
3V3_ADC_A
1V1_CORE
PI_3V3 -> 3V3_D on HAT+
```

## Placement policy

Use a continuous ground plane; control noise through current-path geometry rather than disconnected analog/digital ground islands.

Hard rules:

- switcher hot loops stay in the digital/power region;
- no SW node or inductor near/under the ferrite, OPA810, LTC1562 or TCXO;
- LT3042/OPA2835/LTC1407A form one ADC island;
- TPS7A2033 is local to the SiT5356;
- 5V_AFE branch resistor/bulk capacitor are placed at the branch entrance;
- HAT/USB power returns do not cross the ferrite/input region;
- COMP/FSET resistor is placed immediately at each TPS628502.

These constraints are hard inputs to Quilter.

## Validation

Power measurements remain mandatory, but they are validation rather than component tuning:

1. verify rail values and ramp ordering;
2. measure switcher spectra at the ferrite input;
3. verify no persistent spur corrupts carrier/PM processing;
4. compare ADC code noise with FPGA idle/active;
5. characterize TCXO phase behavior;
6. verify `5V_AFE` at minimum realistic input voltage;
7. verify ECP5 thermal/current margin using the real synthesis/activity profile;
8. repeat Master-SPI boots and HAT STANDBY transitions.

## Sources

- Texas Instruments TPS62850x data sheet.
- Texas Instruments TPS7A20 data sheet.
- Texas Instruments TPS22975/TPS22975N data sheet.
- Analog Devices LT3042 data sheet.
- Lattice ECP5/ECP5-5G Family Data Sheet and Hardware Checklist.
- Murata DFE252012PD inductor documentation.
