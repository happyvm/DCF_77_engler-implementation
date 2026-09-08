# Raspberry Pi HAT+ power split: use both 5 V and 3.3 V

## Decision

The Rev.0 Raspberry Pi HAT+ consumes both power rails provided by the Raspberry Pi 40-pin header:

```text
PI_5V  -> protected/gated path -> 5V_SYS
PI_3V3 -> direct digital rail  -> 3V3_D
```

The standalone USB-C board is unchanged and continues to generate `3V3_D` locally from `5V_SYS`.

## Why use PI_3V3

Using the Raspberry Pi 3.3 V rail for the HAT digital domain avoids recreating an unnecessary 3.3 V switching rail on the HAT PCB.

Benefits:

- removes one switching regulator from the HAT board;
- reduces conversion loss and BOM count;
- removes one local high-frequency switching source near the 77.5 kHz receiver;
- directly matches Raspberry Pi GPIO voltage;
- naturally follows HAT+ STANDBY behavior, where 5 V remains present but 3.3 V is removed.

## Reference HAT+ power architecture

```text
PI_5V
  -> protection / load switch
  -> 5V_SYS
       -> filtered 5V_AFE
       -> LT3042 -> 3V3_ADC_A
       -> TPS7A20 -> 3V3_CLK
       -> TPS628502 -> 1V1_CORE
       -> LCD backlight current path

PI_3V3
  -> current-measure / 0R link
  -> 3V3_D_HAT
       -> ECP5 3.3 V VCCIO banks
       -> ECP5 VCCIO8
       -> W25Q64JV configuration flash
       -> HAT+ ID EEPROM and pull-ups
       -> LCD logic
       -> PPS/output logic at 3.3 V
       -> TPS7A20 -> 2V5_AUX under controlled enable
```

The common logical rail presented to the receiver core remains `3V3_D`; only its source differs by PCB variant.

## Loads that must not use PI_3V3

Keep the sensitive and higher-current domains locally generated from Pi 5 V:

```text
5V_AFE     -> OPA810 / LTC1562 / LTC6912
3V3_ADC_A  -> LTC1407A-1 / OPA2835
3V3_CLK    -> SiT5356 TCXO
1V1_CORE   -> ECP5 VCC
```

The Pi 3.3 V rail is therefore a digital-only source.

## LCD backlight

Do not place the roughly 30 mA LCD backlight load on Raspberry Pi 3.3 V.

```text
LCD logic     -> 3V3_D_HAT
LCD backlight -> 5V_SYS through fixed current limiting and low-side MOSFET
```

The backlight remains off in precision RF mode.

## STANDBY behavior

Current HAT+ rules define STANDBY as:

```text
PI_5V  present
PI_3V3 absent
```

Use `PI_3V3` presence as the HAT-active indication.

Normal behavior:

```text
Pi active:
PI_3V3 valid
  -> 3V3_D_HAT valid
  -> enable HAT 5V_SYS path
  -> enable local rails
  -> ECP5 boots

Pi STANDBY:
PI_3V3 absent
  -> 3V3_D_HAT off
  -> disable HAT 5V_SYS path
  -> local receiver rails off
  -> no HAT GPIO can back-power the Pi
```

Do not provide any alternate source capable of driving `3V3_D_HAT` while `PI_3V3` is absent. JTAG/debug connectors expose the rail only as a voltage reference.

## ECP5 sequencing consequence

On the HAT+, `VCCIO8` and the configuration flash are powered from `PI_3V3` before the local ECP5 core rail is enabled:

```text
PI_3V3 / 3V3_D valid
       -> VCCIO8 valid
       -> W25Q64JV valid
       -> HAT_ACTIVE
             -> enable 5V_SYS
                  -> enable 1V1_CORE
                  -> enable 2V5_AUX
```

`PROGRAMN` remains controlled so configuration does not begin until required rails are valid.

## Raspberry Pi interface bank

All ECP5 pins connected directly to Raspberry Pi GPIO use a 3.3 V ECP5 bank powered from `3V3_D_HAT`.

Preferred interface:

```text
SPI SCLK
SPI MOSI
SPI MISO
SPI CS
IRQ / DATA_READY
optional RESET/control
PPS copy to Pi GPIO
```

No level shifter is required for normal 3.3 V Pi GPIO operation when both sides share the same 3.3 V domain.

## PI_3V3 current-budget policy

Do not assume unlimited current simply because the header exposes 3.3 V pins.

Before PCB release, estimate and measure current drawn from `PI_3V3` with:

- ECP5 configured and worst-case 3.3 V I/O activity;
- configuration flash active;
- LCD logic active;
- HAT EEPROM present;
- PPS/host interface toggling.

Provide:

```text
PI_3V3 -> 0R/current-measure link -> 3V3_D_HAT
```

ADC, TCXO, AFE, ECP5 core and LCD backlight are deliberately excluded from this budget.

Do not freeze a universal PI_3V3 current limit until the supported Raspberry Pi model set and power documentation are checked.

## Noise policy

Rules:

- local bulk and high-frequency decoupling at the HAT 3.3 V entry;
- short distribution to ECP5 VCCIO and flash;
- no PI_3V3 routing through the ferrite/OPA810/LTC1562 region;
- no use of PI_3V3 as ADC or TCXO supply;
- Pi-facing digital return currents stay in the digital side of the board.

Removing the local HAT 3.3 V buck eliminates one potential self-interference source, while the Raspberry Pi itself remains an RF-noisy neighbor that must be characterized.

## Variant comparison

```text
Standalone USB-C:
5V_SYS -> TPS628502 -> 3V3_D

Raspberry Pi HAT+:
PI_3V3 ------------> 3V3_D
```

Everything downstream of `3V3_D` remains functionally equivalent where possible.

## References

- Raspberry Pi HAT+ Specification, current revision.
- Raspberry Pi GPIO/40-pin header documentation.
- Lattice ECP5/ECP5-5G Hardware Checklist.
