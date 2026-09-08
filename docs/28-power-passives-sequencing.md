# Rev.0 fixed power passives, switching policy and sequencing

## Decision

Rev.0 now targets one Raspberry Pi HAT+ board only. The former standalone USB-C power path and standalone 3.3 V buck are removed.

Reference rails:

```text
PI_5V -> TPS22975NDSGR -> 5V_SYS
  |
  +--> 0.10 ohm + fixed RC bypass -> 5V_AFE
  +--> LT3042EMSE#PBF -> 3V3_ADC_A
  +--> TPS7A2033PDQNR -> 3V3_CLK
  +--> TPS628502DRLR -> 1V1_CORE

PI_3V3 -> current-measure link -> 3V3_D
3V3_D -> TPS7A2025PDQNR -> 2V5_AUX
```

All component values below are fixed reference values. Prototype work validates them; it does not select different values per board.

## 1. Fixed 5V_AFE filter

```text
5V_SYS
   |
R_AFE = 0.10 ohm, 1%, 0805
   |
   +--------- 5V_AFE
   |
   +-- 100 uF / >=10 V low-ESR -> GND
   +--   1 uF / >=10 V X7R    -> GND
   +-- 100 nF / >=10 V X7R    -> GND
```

At 75 mA design load:

```text
DC drop = 7.5 mV
```

The ideal 0.10 ohm / 100 uF pole is approximately 15.9 Hz. There is no LC tuning and no selectable resistor population.

## 2. TPS628502 core implementation

Only one TPS628502 remains on Rev.0:

```text
U_CORE: 5V_SYS -> 1V1_CORE
TPS628502DRLR
```

### Switching configuration

The internal 2.25 MHz nominal setting is not used because:

```text
29 * 77.5 kHz = 2.2475 MHz
```

Reference population:

```text
COMP/FSET -> 5.76 kOhm, 1%, to GND
MODE/SYNC -> logic high through 10 kOhm
SSC       -> disabled
mode      -> forced PWM
nominal fsw ~= 3.125 MHz
```

Forced PWM avoids light-load PFM burst structure. SSC remains disabled so the switching spectrum is deterministic and easier to characterize.

### Inductor

```text
Murata DFE252012PD-R47M=P2
0.47 uH
shielded
```

### Input/output capacitors

```text
CIN  = 10 uF X7R >=10 V
       + 100 nF close to VIN/GND

COUT = 2 x 10 uF X7R >=6.3 V
```

### 1V1_CORE feedback

```text
R_TOP = 39.2 kOhm, 0.1%
R_BOT = 47.0 kOhm, 0.1%
C_FF  = 10 pF C0G/NP0
VOUT ~= 1.100 V
```

## 3. 3V3_ADC_A — LT3042

```text
LT3042EMSE#PBF
RSET = 33.2 kOhm, 0.1% thin film
CSET = 4.7 uF X7R
CIN  = 10 uF X7R, >=10 V
COUT = 10 uF X7R, >=6.3 V
       + local 100 nF at ADC/driver
```

This rail powers only the LTC1407A-1, OPA2835 and ADC-bias island.

## 4. 3V3_CLK — TPS7A20

```text
TPS7A2033PDQNR
CIN  = 2.2 uF X7R, >=10 V
COUT = 2.2 uF X7R, >=6.3 V
100 nF immediately at SiT5356
```

This rail is dedicated to the SiT5356 fixed TCXO.

## 5. 2V5_AUX — TPS7A20

```text
TPS7A2025PDQNR
input = 3V3_D
CIN  = 2.2 uF X7R, >=6.3 V
COUT = 2.2 uF X7R, >=6.3 V
```

Load is ECP5 `VCCAUX`.

## 6. HAT+ 5 V switch

```text
TPS22975NDSGR
PI_5V -> VIN/VBIAS
PI_3V3 -> ON
ON -> 100 kOhm -> GND
CT -> 1.0 nF, >=30 V -> GND
VOUT -> 5V_SYS
```

The N variant is used without quick-output-discharge. The low on-resistance preserves the LTC1562 5 V margin.

## 7. PI_3V3 digital rail

```text
PI_3V3
  -> 0R/current-measure link
  -> 3V3_D
```

At the HAT entry:

```text
10 uF X7R
1 uF X7R
100 nF X7R
```

`3V3_D` powers ECP5 VCCIO/VCCIO8, W25Q64, HAT EEPROM, LCD logic and host/PPS I/O, and feeds the 2.5 V auxiliary LDO.

It must not power AFE, ADC, TCXO, ECP5 core or LCD backlight.

## 8. HAT+ sequencing

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
                    +--> TPS628502 -> 1V1_CORE
                    +--> LT3042 -> 3V3_ADC_A
                    +--> TPS7A2033 -> 3V3_CLK
                    +--> fixed 5V_AFE branch
```

When `PI_3V3` disappears in STANDBY, `3V3_D` disappears and TPS22975N turns off. No alternate source may back-power the Pi-facing domain.

## 9. ECP5 POR / PROGRAMN policy

Lattice internal POR monitors `VCC`, `VCCAUX` and `VCCIO8`. The HAT ordering intentionally establishes the 3.3 V configuration domain before the local 1.1 V core rail.

Reference:

```text
PROGRAMN -> 4.7 kOhm pull-up to VCCIO8
          -> manual/test access
          -> optional open-drain host reset only
```

No arbitrary fixed-delay supervisor is used solely for normal ECP5 boot.

## 10. ECP5 fixed decoupling

### `1V1_CORE`

```text
6 x 100 nF X7R, one per VCC ball
2 x 10 uF X7R bulk near FPGA
```

### `2V5_AUX`

```text
2 x 100 nF X7R, one per VCCAUX ball
1 x 4.7 uF X7R local bulk
```

### `3V3_D` VCCIO

```text
100 nF X7R per VCCIO supply ball
1 uF X7R per populated bank
10 uF X7R near Bank 8 / W25Q64
10 uF X7R near main ECP5 3V3_D entry
```

## 11. Placement rules

The HAT now contains only one switching buck: `1V1_CORE`.

Hard rules:

- `SW` copper minimum practical area;
- inductor immediately adjacent to switch node/output capacitors;
- VIN capacitor immediately adjacent to VIN/GND;
- no switch node/inductor/FSET trace under or near ferrite, OPA810, LTC1562 or TCXO;
- LT3042 stays inside ADC island;
- TPS7A2033 stays beside TCXO;
- 5V_AFE resistor and bulk capacitor sit at branch entrance;
- Pi 3.3 V distribution stays in digital/HAT region.

## 12. Validation is not tuning

Prototype acceptance:

1. check all rail voltages/ramp order;
2. measure 1.1 V buck spectrum at ferrite input;
3. verify no persistent spur corrupts 77.5 kHz carrier/PM band;
4. check ADC-code noise with digital loads idle/active;
5. check TCXO phase behavior;
6. check `5V_AFE` minimum voltage at worst realistic Pi 5 V/load;
7. run ECP5 power estimate and verify thermal margin;
8. repeat boot and HAT STANDBY cycles.

A failed validation causes a board revision, not per-unit component selection.

## Reference BOM subset

| Function | Reference part/value |
|---|---|
| HAT 5 V load switch | `TPS22975NDSGR` |
| core buck | `TPS628502DRLR` |
| core inductor | `DFE252012PD-R47M=P2`, 0.47 uH |
| buck FSET | 5.76 kOhm 1%, SSC off |
| buck mode | forced PWM |
| core divider | 39.2 k / 47.0 k / 10 pF |
| ADC LDO | `LT3042EMSE#PBF`, RSET 33.2 k |
| clock LDO | `TPS7A2033PDQNR` |
| aux LDO | `TPS7A2025PDQNR` |
| AFE series resistor | 0.10 ohm, 1% |

## References

- TI TPS62850x data sheet.
- TI TPS7A20 data sheet.
- TI TPS22975/TPS22975N data sheet.
- ADI LT3042 data sheet.
- Lattice ECP5/ECP5-5G hardware/configuration documentation.
- Murata DFE252012PD documentation.
