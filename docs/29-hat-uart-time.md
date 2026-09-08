# Raspberry Pi HAT+ UART date/time telemetry

## Decision

Rev.0 adds a dedicated 3.3 V UART between the ECP5 and Raspberry Pi for low-rate DCF77 date/time telemetry.

The UART complements the existing host interfaces:

```text
SPI   -> control, diagnostics and higher-rate data
UART  -> simple date/time/status telemetry
PPS   -> hardware timing reference
```

The UART does **not** replace the dedicated external PPS output and must not be used as the precision second-edge reference.

## Physical mapping

Signal names are relative to the ECP5.

```text
ECP5 HAT_UART_TX
A13 / PT83A
  -> 33 ohm
  -> Raspberry Pi physical pin 10 / GPIO15 / RXD

Raspberry Pi physical pin 8 / GPIO14 / TXD
  -> 33 ohm
  -> ECP5 HAT_UART_RX
     A14 / PT83B
```

Both ECP5 pins are in Bank 1 and therefore use:

```text
VCCIO1 = 3V3_D = PI_3V3
```

No level translator is required.

Keep `A12 / PT71B` spare. This avoids placing the UART on the direct companion ball of the HAT PPS signal `A11 / PT71A`.

## Electrical policy

Reference population:

```text
series resistance = 33 ohm on each UART line
idle pull-up       = 47 kOhm to 3V3_D on each UART line
logic level        = 3.3 V only
```

Place the source-series resistor close to the active source where practical:

- ECP5 TX resistor close to `A13`;
- Pi TX resistor close to the 40-pin HAT connector.

The weak pull-ups keep both UART nets at their normal idle-high state while either endpoint is resetting/configuring. They are not intended as logic-level conversion or strong termination.

## Serial format

Reference configuration:

```text
baud         115200
format       8N1
data bits    8
parity       none
stop bits    1
flow control none
```

The physical link is bidirectional, but the principal Rev.0 use is FPGA -> Raspberry Pi.

## Time frame

Reference ASCII frame:

```text
$DCF77,YYYYMMDD,HHMMSS,+HHMM,S,QQQ*CS\r\n
```

Example shape:

```text
$DCF77,20260908,181234,+0200,L,087*XX\r\n
```

Fields:

```text
YYYYMMDD  decoded civil date
HHMMSS    decoded DCF77 civil time
+HHMM     explicit UTC offset, normally +0100 CET or +0200 CEST
S         receiver state
QQQ       signal/decoder quality 000...100
CS        two hexadecimal checksum digits
```

Receiver-state characters:

```text
L = locked / synchronized
H = holdover using the disciplined local clock
U = unsynchronized / time not yet trustworthy
```

`CS` is the 8-bit XOR of the ASCII bytes strictly between `$` and `*`, rendered as two uppercase hexadecimal digits.

Maximum reference-frame length is **64 bytes**, including line termination. This leaves timing margin and prevents diagnostics from silently turning the UART into a continuous high-activity data link.

## Transmission timing / RF policy

Do not transmit continuously.

The DCF77 phase-modulation sequence ends at approximately:

```text
992.774 ms
```

within each ordinary second. Rev.0 therefore schedules the once-per-second UART frame approximately inside:

```text
993 ... 999 ms
```

At 115200 baud with 8N1, one byte occupies approximately 86.8 us and 64 bytes require approximately 5.56 ms. Therefore the complete maximum reference frame fits inside this tail window.

This timing policy keeps UART switching outside the principal AM and PM observation intervals. If a future frame no longer fits, shorten the frame or defer optional diagnostics; do not extend routine UART activity into the sensitive receive interval merely for convenience.

## Relationship to PPS

The Pi receives two different timing products:

```text
GPIO4 PPS
  -> actual ECP5-generated second event
  -> use for timestamping / kernel PPS discipline

UART date/time frame
  -> labels/status associated with that timebase
  -> use for calendar date, civil time, lock state and quality
```

Software should associate the received UART frame with the corresponding PPS event rather than timestamping the UART byte arrival as the DCF77 second edge.

## Raspberry Pi configuration

The 40-pin header uses:

```text
physical 8  = GPIO14 / TXD
physical 10 = GPIO15 / RXD
```

On Raspberry Pi OS, enable the serial-port hardware and disable the login console on that UART. `raspi-config` normally exposes this under the serial-port interface options.

Do not hard-code one Linux device path for every Raspberry Pi generation. In particular, Raspberry Pi 5 changes the default primary/debug UART arrangement. Host software must use the UART actually configured onto GPIO14/GPIO15.

## RTL boundary

The platform layer owns the physical UART serializer/deserializer. Suggested boundary:

```text
rtl/platform/uart_tx.sv
rtl/platform/uart_rx.sv          future if Pi->FPGA commands are required in RTL
rtl/core/time_telemetry.sv       future formatter/state source
```

The initial hardware deliverable includes the transmitter primitive. The date/time formatter should consume the final decoder outputs rather than duplicate calendar-decoding logic inside the UART block.

## Layout rules

- keep both UART traces in the Bank-1/HAT digital region;
- no UART trace may detour toward the ferrite/OPA810/LTC1562 region;
- keep the lines away from the TCXO clock escape where practical;
- no connector/test stub on the UART lines unless explicitly required;
- maintain the once-per-second tail-window activity policy in normal operation.

## Sources

- Raspberry Pi 40-pin GPIO/UART documentation.
- Raspberry Pi UART configuration documentation.
- Lattice ECP5U-45 BG256 pinout, `FPGA-SC-02034`.
- exact-device third-party schematic cross-check for the `PT83A/PT83B` Bank-1 ball names.
