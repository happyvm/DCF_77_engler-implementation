# Rev.0 power-tree architecture

## Decision

Rev.0 is now **Raspberry Pi HAT+ only**. The former standalone USB-C power shell and its local 3.3 V buck have been removed.

Reference HAT power entry:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure / 0R link -> 3V3_D
```

Sensitive analog/clock rails remain locally generated from `PI_5V`; the Pi 3.3 V rail is used only for the digital I/O/configuration domain.

Exact values are mirrored in:

- [`28-power-passives-sequencing.md`](28-power-passives-sequencing.md)
- [`../hardware/tscircuit/power-plan.json`](../hardware/tscircuit/power-plan.json)

## Rail architecture

```text
PI_5V
  -> TPS22975NDSGR
  -> 5V_SYS
       +--> 0.10 ohm fixed branch -> 5V_AFE
       |      -> OPA810 / LTC1562 / LTC6912
       |
       +--> LT3042EMSE#PBF -> 3V3_ADC_A
       |      -> LTC1407A-1 / OPA2835
       |
       +--> TPS7A2033PDQNR -> 3V3_CLK
       |      -> SiT5356 25 MHz TCXO
       |
       +--> TPS628502DRLR -> 1V1_CORE
              -> ECP5 VCC

PI_3V3
  -> current-measure / 0R link
  -> 3V3_D
       +--> ECP5 VCCIO / VCCIO8
       +--> W25Q64JV
       +--> HAT EEPROM
       +--> LCD logic
       +--> PPS / Pi host I/O
       +--> TPS7A2025PDQNR -> 2V5_AUX -> ECP5 VCCAUX
```

## Fixed 5V_AFE branch

```text
5V_SYS
  -> 0.10 ohm, 1%, 0805
  -> 5V_AFE
       -> 100 uF low-ESR
       -> 1 uF X7R
       -> 100 nF X7R
```

At the conservative 75 mA AFE design budget, the resistor drops about 7.5 mV.

There is no per-board resistor selection or ferrite-bead tuning.

## 3V3_ADC_A

```text
LT3042EMSE#PBF
RSET = 33.2 kOhm, 0.1%
CSET = 4.7 uF
CIN  = 10 uF X7R
COUT = 10 uF X7R
```

Loads are the LTC1407A-1 ADC, OPA2835 driver and local ADC bias network.

## 3V3_CLK

```text
TPS7A2033PDQNR
CIN  = 2.2 uF X7R
COUT = 2.2 uF X7R
100 nF directly at SiT5356
```

This rail is dedicated to the fixed 25 MHz SiT5356.

## 2V5_AUX

```text
TPS7A2025PDQNR
input = 3V3_D
CIN   = 2.2 uF X7R
COUT  = 2.2 uF X7R
```

Load is ECP5 `VCCAUX`.

## 1V1_CORE

Reference converter:

```text
TPS628502DRLR
L = DFE252012PD-R47M=P2, 0.47 uH
CIN = 10 uF + 100 nF
COUT = 2 x 10 uF X7R
```

Reference operating mode:

```text
COMP/FSET = 5.76 kOhm
nominal fsw ~= 3.125 MHz
SSC = OFF
MODE/SYNC = HIGH
forced PWM
```

The internal 2.25 MHz nominal setting is intentionally avoided because:

```text
29 * 77.5 kHz = 2.2475 MHz
```

The reference feedback is:

```text
R_TOP = 39.2 kOhm, 0.1%
R_BOT = 47.0 kOhm, 0.1%
C_FF  = 10 pF C0G
VOUT ~= 1.100 V
```

There is no longer a second TPS628502 for a standalone 3.3 V rail.

## HAT+ input switch

```text
TPS22975NDSGR
VIN/VBIAS = PI_5V
ON        = PI_3V3
ON pulldown = 100 kOhm
CT        = 1.0 nF, >=30 V
VOUT      = 5V_SYS
```

When `PI_3V3` disappears in HAT+ STANDBY, the switch turns off and all locally generated receiver rails collapse.

## ECP5 sequencing

Reference sequence:

```text
PI_3V3 valid
   -> 3V3_D / VCCIO8 / W25Q64 valid
   -> 2V5_AUX starts
   -> TPS22975N enables 5V_SYS
   -> 1V1_CORE / 3V3_ADC_A / 3V3_CLK / 5V_AFE start
   -> ECP5 internal POR releases after VCC/VCCAUX/VCCIO8 thresholds
```

`PROGRAMN` keeps its normal pull-up, manual test access and optional open-drain reset path. No arbitrary-delay supervisor is used solely for normal boot.

## ECP5 decoupling baseline

```text
1V1_CORE:
  6 x 100 nF local
  2 x 10 uF bulk

2V5_AUX:
  2 x 100 nF local
  1 x 4.7 uF bulk

3V3_D / VCCIO:
  100 nF per VCCIO supply ball
  1 uF per populated bank
  10 uF near Bank 8 / W25Q64
  10 uF at main ECP5 3V3_D entry
```

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

Provide current-measure links for at least `5V_AFE`, `3V3_ADC_A`, `1V1_CORE` and `PI_3V3 -> 3V3_D`.

## Placement policy

Use one continuous ground reference while controlling return currents by placement.

Hard rules:

- the only local buck hot loop is the ECP5 1.1 V converter;
- no SW node/inductor near the ferrite, OPA810, LTC1562 or TCXO;
- LT3042/OPA2835/LTC1407A remain one tight ADC island;
- TPS7A2033 remains local to the SiT5356;
- the 5V_AFE branch resistor/bulk capacitor are placed at the branch entrance;
- Pi supply/host return currents stay in the digital/HAT-header region.

## Validation

1. verify all rail values and ramp ordering;
2. measure the 1.1 V buck spectrum at the ferrite input;
3. verify no persistent spur corrupts carrier/PM processing;
4. compare ADC code noise with FPGA idle/active;
5. characterize TCXO phase behavior;
6. verify `5V_AFE` at minimum realistic Pi 5 V;
7. verify ECP5 current/thermal margin from real synthesis/activity;
8. repeat Master-SPI boots and HAT STANDBY cycles.

## Sources

- Texas Instruments TPS62850x data sheet.
- Texas Instruments TPS7A20 data sheet.
- Texas Instruments TPS22975/TPS22975N data sheet.
- Analog Devices LT3042 data sheet.
- Lattice ECP5/ECP5-5G Family Data Sheet and Hardware Checklist.
- Murata DFE252012PD inductor documentation.
