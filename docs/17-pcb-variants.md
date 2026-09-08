# PCB variants: Raspberry Pi HAT+ and standalone USB-C

## Decision

The receiver is built as two PCB variants sharing one receiver architecture:

1. **Raspberry Pi HAT+**;
2. **standalone USB-C**.

The AFE, ADC, ECP5, clocking, display behavior, PPS generation and RTL remain common wherever practical.

```text
antenna -> AFE -> PGA -> ADC -> ECP5 -> timing/decoder
                                  |
                                  +-> fixed TCXO discipline
                                  +-> LCD
                                  +-> hardware PPS
                                  +-> host/debug
```

# Mandatory PPS and LCD

Both variants expose a dedicated ECP5-generated hardware PPS. The rising edge is the metrology reference and must remain measurable independently of Linux or USB.

Both variants use the same Rev.0 transflective 20x2 LCD. The display is never required for timing operation and its backlight is disabled during precision RF measurements.

# Variant A — Raspberry Pi HAT+

## Standard

Follow the current Raspberry Pi HAT+ specification, not the deprecated original HAT specification.

The board is a **Standard HAT+**. It consumes power from the Raspberry Pi and never sources power back into it.

## HAT+ uses both Pi power rails

Rev.0 deliberately consumes both header rails:

```text
PI_5V  -> protected/gated path -> 5V_SYS
PI_3V3 -> HAT digital rail     -> 3V3_D
```

This replaces the earlier all-from-5V HAT concept.

### PI_5V domain

`PI_5V` powers the receiver functions that need local regulation or low-noise isolation:

```text
PI_5V
  -> 5V_SYS
       -> filtered 5V_AFE
       -> LT3042 -> 3V3_ADC_A
       -> TPS7A20 -> 3V3_CLK
       -> TPS628502 -> 1V1_CORE
       -> LCD backlight path
```

### PI_3V3 domain

`PI_3V3` directly supplies the HAT digital 3.3 V domain:

```text
PI_3V3
  -> current-measure / 0R link
  -> 3V3_D
       -> ECP5 VCCIO / VCCIO8
       -> W25Q64JV configuration flash
       -> HAT+ ID EEPROM
       -> LCD logic
       -> PPS / Pi-host I/O domain
       -> controlled TPS7A20 -> 2V5_AUX
```

The HAT therefore does not need the standalone board's 3.3 V buck converter.

`PI_3V3` is digital-only and must not power the ADC, ADC driver, TCXO, AFE, ECP5 core or LCD backlight.

Detailed policy: [`26-hat-power.md`](26-hat-power.md).

## HAT+ STANDBY

The HAT+ specification defines STANDBY with 5 V still present but 3.3 V absent.

Use `PI_3V3` presence as the HAT-active condition:

```text
PI_3V3 present -> 3V3_D valid -> enable 5V_SYS/local rails
PI_3V3 absent  -> 3V3_D off   -> disable 5V_SYS/local rails
```

No alternate source may back-power `3V3_D` while Pi 3.3 V is absent.

This naturally prevents ECP5/PPS/SPI outputs from driving an unpowered Raspberry Pi GPIO domain.

## HAT EEPROM

Reserve the HAT+ identification EEPROM on the dedicated ID pins and Pi 3.3 V domain. Keep identification traffic separate from receiver runtime SPI.

## Raspberry Pi host interface

Preferred runtime interface:

```text
SPI host link
IRQ / DATA_READY
optional reset/control
PPS copy to Pi GPIO
```

Raw ADC streaming is a diagnostic mode, not the normal host requirement.

The ECP5 pins connected to Raspberry Pi GPIO are assigned to a 3.3 V bank powered by `PI_3V3`.

## HAT PI_3V3 current budget

Do not assume unlimited header 3.3 V current.

Provide a current-measure link and validate the real load for the supported Raspberry Pi models.

The budget contains only:

- ECP5 3.3 V I/O banks;
- configuration flash;
- HAT EEPROM;
- LCD logic;
- low-current host/PPS interface circuitry.

The ADC, TCXO, AFE, FPGA core and LCD backlight are excluded.

## HAT RF concerns

The Raspberry Pi remains a difficult RF neighbor for a 77.5 kHz weak-signal receiver.

Hard requirements:

- ferrite at the board edge farthest from Pi digital/power circuitry;
- no Pi/FPGA fast traces under the antenna/input cluster;
- keep Pi digital return currents out of the analog region;
- characterize CPU, USB, Ethernet and Wi-Fi activity;
- preserve the option for a remote active antenna head in difficult installations.

Using Pi 3.3 V removes one local 3.3 V switcher from the HAT, but it does not make the Raspberry Pi electrically quiet.

# Variant B — standalone USB-C

The standalone board remains a 5 V USB-C sink:

```text
USB4105-GF-A
  -> TUSB320LAIRWBR UFP/sink controller
  -> TPS259470ARPWR eFuse
  -> 5V_SYS
```

No USB-PD is required.

Unlike the HAT, standalone generates its own digital 3.3 V rail:

```text
5V_SYS -> TPS628502 -> 3V3_D
```

Everything downstream of `3V3_D` remains functionally equivalent where practical.

Standalone is the cleaner RF/metrology reference board.

See [`25-standalone-usbc-power.md`](25-standalone-usbc-power.md).

# Common power-domain comparison

```text
                          HAT+                 standalone

5V_SYS source             Raspberry Pi 5 V    USB-C 5 V sink
3V3_D source              Raspberry Pi 3.3 V  local TPS628502
5V_AFE                    local filtered       local filtered
3V3_ADC_A                 local LT3042         local LT3042
3V3_CLK                   local TPS7A20        local TPS7A20
1V1_CORE                  local TPS628502      local TPS628502
2V5_AUX                   local LDO            local LDO
```

The sensitive analog/ADC/clock rails therefore remain locally generated on both boards even though the HAT uses Pi 3.3 V for its digital domain.

# Hardware PPS

Both boards provide:

```text
ECP5 disciplined timebase
  -> deterministic PPS output path
  -> external PPS connector/test point
```

The HAT additionally routes a secondary PPS copy to a Pi GPIO.

Acceptance measurements compare:

```text
Delta t = PPS_DCF77 - PPS_GNSS
```

with signal quality, lock state and temperature recorded.

# Validation matrix

| Test | HAT+ | standalone |
|---|---:|---:|
| analog noise floor | measure | measure |
| 77.5 kHz self-spur | measure | measure |
| carrier phase noise | measure | measure |
| AM/PM decoding | same RTL | same RTL |
| clock discipline | same RTL | same RTL |
| PPS offset/jitter | measure | measure |
| sensitivity | compare | baseline |
| 3.3 V digital source noise | Pi rail | local buck |

The difference in `3V3_D` source is deliberate and becomes part of the HAT-versus-standalone comparison.

# tscircuit split

```text
hardware/tscircuit/src/
  core/
    receiver_core.tsx
    afe.tsx
    adc.tsx
    ecp5.tsx
    clock.tsx
    pps.tsx
    display.tsx
    receiver_power.tsx
  variants/
    raspberry_pi_hatplus.tsx
    standalone_usb_c.tsx
  power/
    hat_5v_input.tsx
    usb_c_5v_input.tsx
  host/
    rpi_spi.tsx
    usb_debug.tsx
```

The two boards preserve electrical function and RF intent rather than identical physical coordinates.

## External specifications

- Raspberry Pi HAT+ Specification, current revision.
- Raspberry Pi GPIO/40-pin documentation.
- USB Type-C sink requirements and selected controller/eFuse data sheets.
