# Raspberry Pi HAT+ receiver board

## Decision

Rev.0 now has **one PCB only**: a Raspberry Pi Standard HAT+.

The previously planned standalone USB-C board has been removed from the project. USB-C power, Type-C CC logic, standalone eFuse, standalone 3.3 V buck and standalone-specific host/debug paths are no longer part of the reference design or BOM.

The receiver architecture is therefore:

```text
Raspberry Pi HAT+
    |
    +--> PI_5V / PI_3V3 power
    +--> SPI host/control
    +--> optional PPS copy to Pi GPIO
    |
    v
antenna -> AFE -> PGA -> ADC -> ECP5 -> timing/decoder
                                  |
                                  +-> fixed TCXO discipline
                                  +-> local 20x2 LCD
                                  +-> dedicated external hardware PPS
```

## Standard

Follow the current Raspberry Pi **HAT+** specification, not the deprecated original HAT specification.

The board is a Standard HAT+:

- it consumes power from the Raspberry Pi;
- it never sources 5 V or 3.3 V back into the Pi;
- it reserves the HAT+ ID EEPROM pins;
- it handles Raspberry Pi STANDBY correctly;
- its runtime interface is intentionally narrow.

## Power architecture

Rev.0 deliberately consumes both Raspberry Pi header rails:

```text
PI_5V  -> TPS22975NDSGR -> 5V_SYS
PI_3V3 -> current-measure / 0R link -> 3V3_D
```

### PI_5V domain

```text
PI_5V
  -> TPS22975NDSGR
  -> 5V_SYS
       -> fixed 5V_AFE branch
       -> LT3042 -> 3V3_ADC_A
       -> TPS7A2033 -> 3V3_CLK
       -> TPS628502 -> 1V1_CORE
       -> LCD backlight path
```

### PI_3V3 domain

```text
PI_3V3
  -> current-measure / 0R link
  -> 3V3_D
       -> ECP5 VCCIO banks / VCCIO8
       -> W25Q64JV configuration flash
       -> HAT+ ID EEPROM
       -> LCD logic
       -> PPS / host-I/O domain
       -> TPS7A2025 -> 2V5_AUX
```

`PI_3V3` is digital-only. It must not power the ADC, ADC driver, TCXO, AFE, ECP5 1.1 V core or LCD backlight.

See [`26-hat-power.md`](26-hat-power.md), [`19-power-tree.md`](19-power-tree.md) and [`28-power-passives-sequencing.md`](28-power-passives-sequencing.md).

## HAT+ STANDBY

HAT+ STANDBY keeps Pi 5 V present while Pi 3.3 V is absent.

Reference behavior:

```text
PI_3V3 present -> 3V3_D valid -> TPS22975N ON -> 5V_SYS/local rails on
PI_3V3 absent  -> 3V3_D off   -> TPS22975N off -> local receiver rails off
```

No alternate source may back-power `3V3_D` while `PI_3V3` is absent.

## HAT ID EEPROM

Physical pins 27/28 remain dedicated to HAT identification:

```text
27 = ID_SD
28 = ID_SC
```

They connect only to the HAT ID EEPROM and are not routed through ECP5.

## Raspberry Pi host interface

Reference runtime interface:

```text
SPI0 MOSI
SPI0 MISO
SPI0 SCLK
SPI0 CE0
IRQ / DATA_READY
RESET/control
PPS copy to Pi GPIO
```

Exact mapping is frozen in [`27-ecp5-pin-plan-hat.md`](27-ecp5-pin-plan-hat.md) and `hardware/tscircuit/pin-plan.json`.

Raw ADC streaming remains a diagnostic mode rather than a normal host requirement.

## Hardware PPS

The board provides one **dedicated external PPS** generated directly by the ECP5 disciplined timebase:

```text
DCF77 timing estimator
      -> disciplined ECP5 timebase
      -> PPS generator
      -> dedicated output path
      -> external PPS connector / test point
```

A secondary copy is routed to a Raspberry Pi GPIO for Linux/kernel PPS use. The external hardware PPS remains the metrology reference.

Acceptance measurement:

```text
Delta t = PPS_DCF77 - PPS_GNSS
```

The fixed board delay is calibratable; variable delay/jitter is the timing error of interest.

## LCD

Rev.0 keeps the local transflective 20x2 LCD:

```text
NHD-C0220BIZ-FSW-FBW-3V3M
3.3 V I2C logic
separately switched backlight
```

The LCD is never required for timing operation. Backlight is OFF during precision RF measurements.

## RF placement consequences

The Raspberry Pi is the only host/power environment now considered, so HAT-specific EMI constraints are mandatory:

- ferrite at the board edge farthest from Pi digital/power circuitry;
- no Pi/FPGA fast traces beneath the antenna/input cluster;
- Pi supply and host-current returns stay in the digital region;
- TCXO, ADC and AFE keep their own local low-noise rails;
- the 1.1 V core buck is kept far from ferrite/OPA810/LTC1562;
- preserve the option for a remote active antenna head in difficult installations.

## Validation

Rev.0 validation is now HAT-only:

| Test | Requirement |
|---|---|
| analog noise floor | measure on HAT |
| 77.5 kHz self-spur | measure with Pi idle and loaded |
| carrier phase noise | measure |
| AM/PM decoding | regression + live reception |
| clock discipline | validate with selected TCXO |
| PPS offset/jitter | compare against GNSS |
| Pi CPU/USB/Ethernet/Wi-Fi interference | characterize |
| PI_3V3 current | measure |
| HAT STANDBY | repeated power-cycle validation |

There is no longer a standalone board used as a comparison baseline.

## tscircuit structure

The source tree is simplified to one board:

```text
hardware/tscircuit/
  pin-plan.json
  power-plan.json
  src/
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      pps.tsx
      display.tsx
      receiver_power.tsx
    board/
      raspberry_pi_hatplus.tsx
      hatplus_constraints.ts
      quilter.ts
    host/
      rpi_spi.tsx
    power/
      hat_5v_input.tsx
```

## External specifications

- Raspberry Pi HAT+ Specification.
- Raspberry Pi 40-pin GPIO documentation.
- Lattice ECP5/ECP5-5G hardware/configuration documentation.
