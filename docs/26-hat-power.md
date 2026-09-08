# Raspberry Pi HAT+ power split: use both 5 V and 3.3 V

## Decision

Rev.0 is a Raspberry Pi HAT+ only and consumes both rails provided by the 40-pin header:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure / 0R link -> 3V3_D
```

Using Pi 3.3 V for the HAT digital domain removes an unnecessary local 3.3 V switching converter while keeping all sensitive analog/clock rails locally regulated from Pi 5 V.

## Exact HAT+ input switch

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

The low RON matters because `5V_AFE` feeds the LTC1562 through only a 0.10-ohm filter resistor and has little voltage-drop budget.

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
       +--> SPI / UART / PPS / Pi host-I/O domain
       +--> TPS7A2025PDQNR -> 2V5_AUX
```

Exact downstream values are frozen in `docs/28-power-passives-sequencing.md` and `hardware/tscircuit/power-plan.json`.

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

HAT+ STANDBY gives:

```text
PI_5V  present
PI_3V3 absent
```

Reference behavior:

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

No alternate supply may drive `3V3_D` while `PI_3V3` is absent. JTAG/debug uses `3V3_D` only as a voltage reference.

## ECP5 sequencing

The HAT naturally establishes the configuration domain before the core rail:

```text
PI_3V3
   -> VCCIO8
   -> W25Q64JV
   -> 2V5_AUX
   -> enable TPS22975N
        -> 5V_SYS
             -> 1V1_CORE
```

Lattice internal POR monitors VCC, VCCAUX and VCCIO8. Rev.0 therefore does not add an arbitrary-delay supervisor solely to hold `PROGRAMN` low.

## Raspberry Pi interface bank

All direct Pi/ECP5 signals are in ECP5 Bank 1 powered by `3V3_D = PI_3V3`:

```text
SPI0 SCLK
SPI0 MOSI
SPI0 MISO
SPI0 CE0
UART TX/RX on GPIO15/GPIO14
IRQ / DATA_READY
RESET/control
PPS copy to Pi
```

No level shifter is required.

UART is a low-rate date/time/status path at 115200 8N1; normal traffic is scheduled near the end of each second rather than being left continuously active.

Exact mapping is frozen in:

- `docs/27-ecp5-pin-plan-hat.md`
- `docs/29-hat-uart-time.md`
- `hardware/tscircuit/pin-plan.json`

## HAT ID EEPROM

```text
physical 27 / ID_SD -> EEPROM SDA
physical 28 / ID_SC -> EEPROM SCL
```

The ID bus is supplied from `PI_3V3` and does not connect to ECP5.

## PI_3V3 current measurement

Reference insertion point:

```text
PI_3V3
  -> 0-ohm/current-measure link
  -> 3V3_D
```

Measured budget includes:

- ECP5 VCCIO-bank current;
- W25Q64 configuration activity;
- LCD logic;
- HAT EEPROM;
- SPI/UART/PPS host-interface switching;
- 2V5_AUX input power.

It excludes ADC, TCXO, AFE, ECP5 core and LCD backlight.

Before PCB release, validate this current against supported Raspberry Pi model/PSU documentation and measure it on real hardware.

## HAT local decoupling

At `PI_3V3 -> 3V3_D` entry:

```text
10 uF X7R
1 uF X7R
100 nF X7R
```

Then apply the per-bank/per-ball ECP5 decoupling from `docs/28-power-passives-sequencing.md`.

## LCD power

```text
LCD logic     -> 3V3_D / PI_3V3
LCD backlight -> 5V_SYS through fixed current limiting and MOSFET control
```

Backlight remains OFF in precision RF mode.

## Noise policy

Hard rules:

- PI_3V3 stays in the digital partition;
- PI_5V reaches the power branch without crossing the AFE first;
- no Pi supply trace runs through ferrite/OPA810/LTC1562 cluster;
- Pi-facing digital current returns remain on the digital side;
- UART traces remain in the Bank-1/HAT region and routine UART traffic is end-of-second only;
- the only local switcher is the ECP5 1.1 V core buck;
- TCXO and ADC retain dedicated low-noise LDOs.

## References

- Raspberry Pi HAT+ Specification.
- Raspberry Pi 40-pin GPIO/UART documentation.
- Texas Instruments TPS22975/TPS22975N data sheet.
- Lattice ECP5/ECP5-5G Family Data Sheet and Hardware Checklist.
