# Rev.0 ECP5 bank plan and Raspberry Pi HAT+ GPIO mapping

## Decision

Rev.0 has one PCB only: Raspberry Pi Standard HAT+ with `LFE5U-45F-7BG256I`.

Goals:

- keep all ECP5 user I/O at 3.3 V;
- place the 25 MHz TCXO on a true primary-clock input;
- keep ADC/PGA traffic next to the ADC boundary;
- keep Raspberry Pi SPI/UART/PPS traffic next to the HAT header;
- keep external PPS/LCD on a separate bank;
- leave left-side banks quiet/spare near the ferrite/AFE;
- reserve Bank 8 for configuration/JTAG.

RTL module interfaces remain vendor-neutral.

## Source hierarchy

Authoritative source: Lattice `ECP5U-45 Pinout`, `FPGA-SC-02034`, exact BG256 package.

The assignments were also cross-checked against a published board using the same `LFE5U-45F-7BG256I`, but third-party material remains only a cross-check.

Before fabrication, compare the tscircuit FPGA symbol mechanically against the current Lattice CSV and package drawing.

# 1. VCCIO policy

All populated ECP5 I/O banks use the Pi-supplied digital rail:

```text
3V3_D = PI_3V3

VCCIO0 = 3V3_D
VCCIO1 = 3V3_D
VCCIO2 = 3V3_D
VCCIO3 = 3V3_D
VCCIO6 = 3V3_D
VCCIO7 = 3V3_D
VCCIO8 = 3V3_D
```

This removes normal inter-bank level shifting from Rev.0.

BG256 VCCIO balls:

| Bank | VCCIO balls |
|---:|---|
| 0 | `F6`, `F7` |
| 1 | `F10`, `F11` |
| 2 | `H11`, `J11` |
| 3 | `K11`, `L11` |
| 6 | `J6`, `J7` |
| 7 | `H6`, `H7` |
| 8 | `L6` |

Core/auxiliary:

```text
VCC 1.1 V: G6, G7, G9, L8, L9, L10
VCCAUX 2.5 V: G11, L7
```

# 2. Functional bank allocation

```text
Bank 0  -> spare / low-rate future control
Bank 1  -> TCXO + Raspberry Pi HAT+ SPI/UART/PPS host interface
Bank 2  -> LTC1407A ADC + LTC6912 control
Bank 3  -> reference PPS + LCD + diagnostics
Bank 6  -> reserve / keep quiet near AFE
Bank 7  -> reserve / keep quiet near AFE
Bank 8  -> configuration flash + JTAG only
```

Banks 6/7 are intentionally quiet so fast external routing does not need to cross the ferrite/OPA810 side.

# 3. Reference 25 MHz clock

```text
SiT5356 25 MHz LVCMOS
    -> ECP5 C9
       PT47B / GR_PCLK1_1
       Bank 1
```

| Signal | Ball | ECP5 function | Direction |
|---|---|---|---|
| `CLK_25M` | **C9** | `PT47B/GR_PCLK1_1` | input |

Reserve `B9` (`PT47A/GR_PCLK1_0`) as an optional lab clock only; do not create a long reference-board stub.

# 4. LTC1407A ADC — Bank 2

| Signal | Ball | ECP5 pin name | Direction at ECP5 |
|---|---|---|---|
| `ADC_SCK` | **J16** | `PR32A/PCLKT2_1` | output |
| `ADC_SDO` | **J15** | `PR32B/PCLKC2_1` | input |
| `ADC_CONV` | **K16** | `PR32C/PCLKT2_0` | output |

`K15` remains spare beside the ADC cluster.

# 5. LTC6912 PGA control — Bank 2

| Signal | Ball | ECP5 pin name | Direction |
|---|---|---|---|
| `PGA_SCK` | **H12** | `PR26A` | output |
| `PGA_MOSI` | **H13** | `PR26B` | output |
| `PGA_CS_N` | **J12** | `PR26D` | output |

Gain updates remain scheduled near the ~995 ms tail after the DCF77 PM sequence.

# 6. Hardware PPS and LCD — Bank 3

| Signal | Ball | ECP5 pin name | Direction |
|---|---|---|---|
| `PPS_REF` | **R12** | `PR65A` | output |
| `LCD_SCL` | **M13** | `PR44C` | bidirectional/open-drain |
| `LCD_SDA` | **N14** | `PR44D` | bidirectional/open-drain |
| `LCD_RST_N` | **M14** | `PR41D` | output |
| `LCD_BL_EN` | **R13** | `PR62C` | output |

`PPS_REF` feeds the dedicated external output path. A separate internal copy reaches the Pi GPIO.

The LCD I2C bus should normally run at 100 kHz and remain idle except for changed characters.

# 7. Raspberry Pi 40-pin HAT+ host interface

Reference mapping:

| Function | Raspberry Pi GPIO | Physical pin | ECP5 ball | Direction |
|---|---:|---:|---|---|
| `HAT_SPI_MOSI` | GPIO10 | **19** | **A10** (`PT51B`) | Pi -> ECP5 |
| `HAT_SPI_MISO` | GPIO9 | **21** | **D11** (`PT69A`) | ECP5 -> Pi |
| `HAT_SPI_SCLK` | GPIO11 | **23** | **A9** (`PT51A`) | Pi -> ECP5 |
| `HAT_SPI_CS_N` | GPIO8 / CE0 | **24** | **E11** (`PT69B`) | Pi -> ECP5 |
| `HAT_IRQ` | GPIO25 | **22** | **C12** (`PT74B`) | ECP5 -> Pi |
| `HAT_RESET_N` | GPIO24 | **18** | **B12** (`PT74A`) | Pi -> ECP5 |
| `HAT_PPS` | GPIO4 | **7** | **A11** (`PT71A`) | ECP5 -> Pi |
| `HAT_UART_TX` | GPIO15 / RXD | **10** | **A13** (`PT83A`) | ECP5 -> Pi |
| `HAT_UART_RX` | GPIO14 / TXD | **8** | **A14** (`PT83B`) | Pi -> ECP5 |

Signal names `HAT_UART_TX/RX` are relative to the ECP5.

All host-interface balls are in Bank 1 and powered by `3V3_D = PI_3V3`.

## UART electrical and timing policy

Reference UART:

```text
115200 baud
8 data bits
no parity
1 stop bit
no flow control
```

Reference wiring:

```text
ECP5 A13/PT83A -> 33R -> Pi GPIO15/RXD, physical pin 10
Pi GPIO14/TXD, physical pin 8 -> 33R -> ECP5 A14/PT83B

HAT_UART_TX -> 47k -> 3V3_D
HAT_UART_RX -> 47k -> 3V3_D
```

The 47 kOhm resistors hold the asynchronous lines in the normal idle-high state while one endpoint is resetting/configuring.

Normal operation sends one short date/time/status frame per second. Keep the reference frame at or below 64 bytes and schedule it approximately in the `993...999 ms` tail after the DCF77 PM sequence. At 115200 8N1, 64 bytes require about 5.56 ms.

See [`29-hat-uart-time.md`](29-hat-uart-time.md) for the frame format and Raspberry Pi software policy.

## Sideband electrical policy

```text
HAT_RESET_N -> 10 kOhm pull-up to PI_3V3
HAT_IRQ     -> defined inactive state in FPGA; optional weak pull-down footprint
HAT_PPS     -> defined low until timebase valid
```

Provide ~33 ohm source-series damping on SPI clock/data outputs and PPS/IRQ where practical.

Use modest SPI rate in normal operation; raw ADC streaming is diagnostic mode. UART is reserved for low-rate time/date telemetry rather than raw sample streaming.

# 8. HAT+ ID EEPROM

ID pins do **not** connect to ECP5:

```text
physical 27 = GPIO0 / ID_SD
physical 28 = GPIO1 / ID_SC
```

Reference implementation:

```text
CAT24C32-compatible 3.3 V EEPROM
address = 0x50
ID_SD -> SDA
ID_SC -> SCL
SDA/SCL -> 3.9 kOhm pull-ups to PI_3V3
WP -> test point + 1 kOhm pull-up to PI_3V3
```

# 9. Raspberry Pi pins intentionally unused

Rev.0 intentionally leaves free:

- GPIO2/GPIO3 (`I2C1`);
- GPIO7/CE1;
- remaining unneeded GPIOs.

GPIO14/GPIO15 are no longer free; they are dedicated to the DCF77 UART.

# 10. ECP5 Bank 8 exact balls

```text
D7/IO7        T6
D6/IO6        R6
D5/IO5        R7
D4/IO4        P7
D3/IO3        N7
D2/IO2        M7
D1/MISO       T7
D0/MOSI       T8
CSN           R8
CS1N          P8
CSSPIN        N8
DOUT/CSON     M8
WRITEN        M9
MCLK          N9
INITN         T9
PROGRAMN      R9
DONE          P9
CFG1          P10
CFG2          R10
CFG0          N10
TDO           M10
TCK           T10
TDI           R11
TMS           T11
```

Reference Master SPI:

```text
W25Q64 /CS  <- CSSPIN N8
W25Q64 CLK  <- MCLK   N9
W25Q64 DI   <- MOSI   T8
W25Q64 DO   -> MISO   T7
```

`MOSI/MISO` use 10 kOhm pull-ups, `CSSPIN` 4.7 kOhm, `MCLK` 1 kOhm.

# 11. Layout consequences

```text
HAT header / top edge
       |
   Bank 1 TCXO + SPI + UART + HAT PPS
       |
      ECP5
       |------ Bank 2 -> ADC/PGA boundary
       |------ Bank 3 -> PPS/LCD edge

quiet banks 6/7 toward ferrite/AFE side
```

Hard routing rules:

- `CLK_25M` short/direct SiT5356 -> `C9`;
- ADC digital cluster kept together;
- HAT SPI/UART stays in the digital/top region;
- UART activity is normally confined to the end-of-second tail;
- `PPS_REF` routes directly to output buffer/connector;
- no Bank 1/2/3 fast signal detours through ferrite/OPA810 region;
- unused Bank 6/7 pins get no decorative test routing.

`A12/PT71B` stays spare between the HAT PPS pair and the UART pair rather than becoming another routine digital signal.

# 12. Machine-readable source

Assignments are mirrored in:

```text
hardware/tscircuit/pin-plan.json
```

The tscircuit ECP5 wrapper and generated LPF constraints must be derived from or checked against this file.

## References

- Lattice ECP5U-45 Pinout, `FPGA-SC-02034`.
- Lattice ECP5/ECP5-5G Family Data Sheet.
- Lattice ECP5/ECP5-5G sysCONFIG User Guide.
- Raspberry Pi HAT+ Specification.
- Raspberry Pi 40-pin GPIO and UART documentation.
