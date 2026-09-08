# Raspberry Pi HAT+ power split: use both 5 V and 3.3 V

## Decision

The Rev.0 Raspberry Pi HAT+ consumes both rails provided by the 40-pin header:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure / 0R link -> 3V3_D
```

The standalone board remains different only at the power/host shell and generates its own `3V3_D` from `5V_SYS`.

Using Pi 3.3 V for the HAT digital domain removes one local switching converter from the receiver board while keeping all sensitive analog/clock rails locally regulated from Pi 5 V.

## Exact HAT+ input switch

Reference part:

```text
TPS22975NDSGR
6 A load-switch class
~16 mOhm typical RON
adjustable rise time
N variant without quick-output-discharge resistor
```

Reference wiring:

```text
PI_5V -> VIN
PI_5V -> VBIAS
PI_3V3 -> ON
ON -> 100 kOhm -> GND
CT -> 1.0 nF, >=30 V -> GND
VOUT -> 5V_SYS
```

At 5 V, the manufacturer table gives about 1.75 ms typical 10%-90% rise time with 1 nF CT.

The low RON matters because `5V_AFE` feeds the LTC1562 directly through only a 0.10-ohm filter resistor and therefore has little voltage-drop budget.

The ON pulldown guarantees that the HAT 5 V receiver path is off when Pi 3.3 V is absent.

## Reference HAT+ power tree

```text
PI_5V
  -> TPS22975NDSGR
  -> 5V_SYS
       +--> 0.10 ohm fixed filter -> 5V_AFE
       +--> LT3042EMSE#PBF -> 3V3_ADC_A
       +--> TPS7A2033PDQNR -> 3V3_CLK
       +--> TPS628502DRLR -> 1V1_CORE
       +--> LCD backlight path

PI_3V3
  -> 0R/current-measure link
  -> 3V3_D
       +--> all ECP5 3.3 V VCCIO banks
       +--> ECP5 VCCIO8
       +--> W25Q64JV configuration flash
       +--> HAT+ ID EEPROM and pull-ups
       +--> LCD logic
       +--> PPS / Pi host-I/O domain
       +--> TPS7A2025PDQNR -> 2V5_AUX
```

Exact downstream power values are frozen in `docs/28-power-passives-sequencing.md` and `hardware/tscircuit/power-plan.json`.

## Loads that never use PI_3V3

`PI_3V3` is a digital I/O/configuration source only.

Do not connect it to:

```text
5V_AFE     -> OPA810 / LTC1562 / LTC6912
3V3_ADC_A  -> LTC1407A-1 / OPA2835
3V3_CLK    -> SiT5356 TCXO
1V1_CORE   -> ECP5 VCC
LCD backlight
```

This prevents Raspberry Pi regulator noise from becoming the final supply for the ADC or timebase.

## STANDBY behavior

HAT+ STANDBY is explicitly useful to our architecture:

```text
PI_5V  present
PI_3V3 absent
```

Normal reference behavior is therefore:

```text
Pi active:
PI_3V3 valid
  -> 3V3_D / VCCIO8 / flash valid
  -> 2V5_AUX valid
  -> TPS22975N ON
  -> 5V_SYS rises with controlled slew
  -> 1V1_CORE / AFE / ADC / TCXO rails start
  -> ECP5 internal POR eventually releases

Pi STANDBY:
PI_3V3 absent
  -> 3V3_D off
  -> TPS22975N forced off by ON pulldown
  -> 5V_SYS and all local receiver rails off
  -> no HAT GPIO back-power path
```

No alternate supply may drive `3V3_D` on the HAT while `PI_3V3` is absent.

JTAG/debug connectors use `3V3_D` only as a voltage reference and never inject power into it.

## ECP5 sequencing consequence

The HAT naturally satisfies the Master-SPI ordering requirement because Pi 3.3 V powers the configuration domain before Pi 5 V is switched into the local core regulator:

```text
PI_3V3
   -> VCCIO8
   -> W25Q64JV
   -> 2V5_AUX
   -> enable TPS22975N
        -> 5V_SYS
             -> 1V1_CORE
```

Lattice's internal POR monitors VCC, VCCAUX and VCCIO8 and does not initialize until its monitored thresholds are met.

Rev.0 therefore does not add an arbitrary-delay supervisor solely to hold `PROGRAMN` low. `PROGRAMN` keeps its normal pull-up, test point and optional open-drain reset path.

## Raspberry Pi interface bank

All direct Pi/ECP5 interface pins are in ECP5 Bank 1 powered by `3V3_D = PI_3V3`:

```text
SPI0 SCLK
SPI0 MOSI
SPI0 MISO
SPI0 CE0
IRQ / DATA_READY
RESET/control
PPS copy to Pi
```

No level shifter is required.

Exact GPIO/ball mapping is frozen in:

- `docs/27-ecp5-pin-plan-hat.md`
- `hardware/tscircuit/pin-plan.json`

## HAT ID EEPROM

The HAT ID bus also runs directly from `PI_3V3` and remains isolated from ECP5:

```text
physical 27 / ID_SD -> EEPROM SDA
physical 28 / ID_SC -> EEPROM SCL
```

No receiver traffic is placed on these pins.

## PI_3V3 current measurement

Do not assume unlimited 3.3 V current from the Raspberry Pi header.

Reference insertion point:

```text
PI_3V3
  -> 0-ohm/current-measure link
  -> 3V3_D
```

The measured budget includes:

- ECP5 VCCIO-bank current;
- W25Q64 configuration activity;
- LCD logic;
- HAT EEPROM;
- PPS/host interface switching;
- 2V5_AUX input power.

It excludes ADC, TCXO, AFE, ECP5 core and LCD backlight.

Before HAT PCB release, check this current against the supported Raspberry Pi model/PSU documentation and measure it on real hardware.

## HAT local decoupling

At the `PI_3V3 -> 3V3_D` entry:

```text
10 uF X7R bulk
1 uF X7R
100 nF X7R
```

Then use the per-bank/per-ball ECP5 decoupling frozen in `docs/28-power-passives-sequencing.md`.

The entry capacitors are placed in the digital/HAT-header region, not beside the ferrite.

## LCD power

```text
LCD logic     -> 3V3_D / PI_3V3
LCD backlight -> 5V_SYS through fixed current limiting and MOSFET control
```

Do not spend about 30 mA of the Pi 3.3 V budget on the backlight.

Backlight remains OFF in precision RF mode.

## Noise policy

The HAT removes its local 3.3 V buck, but the Raspberry Pi remains an electrically noisy neighbor.

Hard rules:

- PI_3V3 stays in the digital partition;
- PI_5V reaches the power branch without crossing the AFE first;
- no Pi supply trace runs through the ferrite/OPA810/LTC1562 cluster;
- Pi-facing digital current returns remain on the digital side;
- the only local switcher on HAT is primarily the ECP5 1.1 V core buck;
- TCXO and ADC retain dedicated low-noise LDOs.

## Variant comparison

```text
Standalone:
5V_SYS -> TPS628502 -> 3V3_D

HAT+:
PI_3V3 ------------> 3V3_D
```

Everything after the logical `3V3_D` boundary remains functionally equivalent where practical.

## References

- Raspberry Pi HAT+ Specification.
- Raspberry Pi 40-pin GPIO documentation.
- Texas Instruments TPS22975/TPS22975N data sheet.
- Lattice ECP5/ECP5-5G Family Data Sheet and Hardware Checklist.
