# Rev.0 ECP5 bank plan and Raspberry Pi HAT+ GPIO mapping

## Decision

Rev.0 now freezes the first pin-planning pass for the `LFE5U-45F-7BG256I` and the Raspberry Pi Standard HAT+ interface.

The goals are:

- keep all ECP5 user I/O at 3.3 V for the first hardware revision;
- place the 25 MHz TCXO on a true ECP5 global primary-clock input;
- keep ADC/PGA traffic on the right-side FPGA banks, next to the ADC boundary;
- keep Raspberry Pi host traffic on the top-side bank, next to the HAT header;
- keep the external PPS and LCD on a separate right-side bank;
- leave the left-side banks quiet/spare so fast digital activity does not need to cross the ferrite/AFE region;
- reserve Bank 8 exclusively for configuration/JTAG functions.

This is a board-level pin assignment. RTL module interfaces remain vendor-neutral.

## Source hierarchy

The authoritative production source remains the Lattice `ECP5U-45 Pinout`, document `FPGA-SC-02034`, for the exact BG256 package.

The pin names/balls below were also cross-checked against the published Numato Mimas ECP5 Mini design, which uses the exact same `LFE5U-45F-7BG256I` device and exposes the bank and primary-clock names clearly.

Before fabrication, the tscircuit FPGA symbol must be mechanically compared against the current Lattice CSV and BGA package drawing; third-party development-board documentation is a cross-check, not the final authority.

# 1. VCCIO policy

Rev.0 uses one 3.3 V logic voltage for every populated ECP5 I/O bank:

```text
VCCIO0 = 3V3_D
VCCIO1 = 3V3_D
VCCIO2 = 3V3_D
VCCIO3 = 3V3_D
VCCIO6 = 3V3_D
VCCIO7 = 3V3_D
VCCIO8 = 3V3_D
```

For the standalone board:

```text
5V_SYS -> local buck -> 3V3_D
```

For the HAT+ board:

```text
PI_3V3 -> current-measure link -> 3V3_D
```

This intentionally removes all normal inter-bank level shifting from Rev.0.

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

Core/auxiliary balls used by the wrapper:

```text
VCC 1.1 V: G6, G7, G9, L8, L9, L10
VCCAUX 2.5 V: G11, L7
```

# 2. Functional bank allocation

```text
Bank 0  -> spare / standalone-side low-rate control
Bank 1  -> TCXO + Raspberry Pi HAT+ host interface
Bank 2  -> LTC1407A ADC + LTC6912 control
Bank 3  -> reference PPS + LCD + local diagnostics
Bank 6  -> reserve / keep quiet near AFE
Bank 7  -> reserve / keep quiet near AFE
Bank 8  -> configuration flash + JTAG only
```

Banks 6/7 are deliberately not filled just because pins exist. Keeping large regions of the FPGA package free from fast external routing gives the PCB floorplanner more freedom to keep the ferrite/OPA810 side electromagnetically quiet.

# 3. Reference 25 MHz clock

Use a dedicated global primary-clock input:

```text
SiT5356 25 MHz LVCMOS
    -> ECP5 C9
       PT47B / GR_PCLK1_1
       Bank 1
```

Reference pin:

| Signal | Ball | ECP5 function | Direction |
|---|---|---|---|
| `CLK_25M` | **C9** | `PT47B/GR_PCLK1_1` | input |

Reserve companion global-clock ball `B9` (`PT47A/GR_PCLK1_0`) as an optional lab/external-clock input only; do not route it to a long connector in the reference population.

# 4. LTC1407A ADC interface — Bank 2

Keep all ADC digital traces as one short cluster between ECP5 and LTC1407A.

Reference assignment:

| Signal | Ball | ECP5 pin name | Direction at ECP5 |
|---|---|---|---|
| `ADC_SCK` | **J16** | `PR32A/PCLKT2_1` | output |
| `ADC_SDO` | **J15** | `PR32B/PCLKC2_1` | input |
| `ADC_CONV` | **K16** | `PR32C/PCLKT2_0` | output |

The adjacent `K15` (`PR32D/PCLKC2_0`) remains spare so the ADC cluster can be changed without disturbing another subsystem.

The converter wrapper continues to produce normalized signed samples to the vendor-neutral RTL.

# 5. LTC6912 PGA control — Bank 2

The PGA serial interface is intentionally sparse and low activity.

| Signal | Ball | ECP5 pin name | Direction |
|---|---|---|---|
| `PGA_SCK` | **H12** | `PR26A` | output |
| `PGA_MOSI` | **H13** | `PR26B` | output |
| `PGA_CS_N` | **J12** | `PR26D` | output |

Gain updates remain scheduled near the ~995 ms tail after the DCF77 PM sequence, so these pins are normally static during the useful receive interval.

# 6. Hardware PPS and LCD — Bank 3

Reference PPS must not share the Raspberry Pi software timing path.

| Signal | Ball | ECP5 pin name | Direction |
|---|---|---|---|
| `PPS_REF` | **R12** | `PR65A` | output |
| `LCD_SCL` | **M13** | `PR44C` | bidirectional/open-drain |
| `LCD_SDA` | **N14** | `PR44D` | bidirectional/open-drain |
| `LCD_RST_N` | **M14** | `PR41D` | output |
| `LCD_BL_EN` | **R13** | `PR62C` | output |

`PPS_REF` feeds the dedicated low-skew output/buffer/connector path. A separate internal copy of the same PPS event is routed to the Raspberry Pi GPIO on the HAT variant; the physical reference output remains independent.

The LCD I2C bus should normally run at 100 kHz and remain idle except for changed characters.

# 7. Raspberry Pi 40-pin HAT+ host interface

Rev.0 uses Raspberry Pi SPI0 plus three low-rate sideband signals.

Reference GPIO mapping:

| Function | Raspberry Pi GPIO | 40-pin physical pin | ECP5 ball | Direction |
|---|---:|---:|---|---|
| `HAT_SPI_MOSI` | GPIO10 | **19** | **A10** (`PT51B`) | Pi -> ECP5 |
| `HAT_SPI_MISO` | GPIO9 | **21** | **D11** (`PT69A`) | ECP5 -> Pi |
| `HAT_SPI_SCLK` | GPIO11 | **23** | **A9** (`PT51A`) | Pi -> ECP5 |
| `HAT_SPI_CS_N` | GPIO8 / CE0 | **24** | **E11** (`PT69B`) | Pi -> ECP5 |
| `HAT_IRQ` | GPIO25 | **22** | **C12** (`PT74B`) | ECP5 -> Pi |
| `HAT_RESET_N` | GPIO24 | **18** | **B12** (`PT74A`) | Pi -> ECP5 |
| `HAT_PPS` | GPIO4 | **7** | **A11** (`PT71A`) | ECP5 -> Pi |

All seven FPGA balls are in Bank 1 and therefore use `3V3_D = PI_3V3` on the HAT.

## Sideband electrical policy

Use deterministic external states because HAT+ GPIOs power up as inputs with weak, implementation-dependent pulls.

```text
HAT_RESET_N -> 10 kOhm pull-up to PI_3V3
HAT_IRQ     -> defined inactive state in FPGA; optional weak pull-down footprint
HAT_PPS     -> defined low until timebase is valid
```

Provide small source-series damping:

```text
33 ohm reference value
```

on SPI clock/data outputs and PPS/IRQ outputs where physically practical. These resistors are digital signal-integrity parts, not per-board tuning components.

Normal host control should use a modest SPI rate. Higher-rate raw ADC streaming is a diagnostic mode and may raise SPI frequency only when requested.

# 8. HAT+ ID EEPROM

The HAT+ ID pins are **not connected to ECP5**.

Use only:

```text
physical pin 27 = GPIO0 / ID_SD
physical pin 28 = GPIO1 / ID_SC
```

for the ID EEPROM, exactly as required by the HAT+ specification.

Reference implementation:

```text
CAT24C32-compatible 3.3 V, 16-bit-addressed EEPROM
Standard HAT+ address = 0x50
ID_SD -> EEPROM SDA
ID_SC -> EEPROM SCL
SDA/SCL -> 3.9 kOhm pull-ups to PI_3V3
WP -> test point + 1 kOhm pull-up to PI_3V3
```

No receiver, FPGA, LCD or host-control signal may be added to ID_SD/ID_SC.

# 9. Raspberry Pi pins intentionally left unused

Do not consume GPIOs merely because they are present.

Rev.0 intentionally leaves available:

- GPIO2/GPIO3 (`I2C1`) — avoids adding traffic to the Pi's normally pulled-up I2C bus;
- GPIO14/GPIO15 — leaves the primary UART free;
- GPIO7/CE1 — second SPI chip-select remains free;
- remaining GPIOs — available for future variant features without changing the reference interface.

This keeps the HAT interface narrow and reduces host-generated switching.

# 10. ECP5 Bank 8 exact package balls

The pin-accurate wrapper must use the following BG256 configuration/JTAG balls:

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

For reference single-bit Master SPI:

```text
W25Q64 /CS  <- CSSPIN N8
W25Q64 CLK  <- MCLK   N9
W25Q64 DI   <- MOSI   T8
W25Q64 DO   -> MISO   T7
```

`MOSI` and `MISO` receive the current Lattice-recommended 10 kOhm pull-ups for Master SPI; `CSSPIN` uses 4.7 kOhm and `MCLK` uses 1 kOhm.

Unused quad pins D2/D3 do not enter the reference boot path.

# 11. Layout consequences

Reference floorplan intent:

```text
HAT header / top edge
       |
   Bank 1 host + TCXO
       |
      ECP5
       |------ Bank 2 -> ADC/PGA analog boundary
       |------ Bank 3 -> PPS/LCD board edge

quiet/reserved banks 6/7 toward ferrite/AFE side
```

Hard routing rules:

- `CLK_25M` is short and direct from SiT5356 to `C9`;
- `ADC_SCK/SDO/CONV` are kept together and do not cross the HAT SPI bundle;
- HAT SPI remains in the digital/top region;
- `PPS_REF` is routed directly toward its output buffer/connector;
- no Bank 1/2/3 fast signal is allowed to detour through the ferrite/OPA810 region;
- unused Bank 6/7 pins should not receive decorative test traces or large headers.

# 12. Machine-readable source

The same assignments are mirrored in:

```text
hardware/tscircuit/pin-plan.json
```

The future tscircuit ECP5 wrapper and generated LPF constraints should be derived from that file or checked against it so schematic pin names and RTL constraints cannot silently diverge.

## References

- Lattice ECP5U-45 Pinout, `FPGA-SC-02034`.
- Lattice ECP5/ECP5-5G Family Data Sheet.
- Lattice ECP5/ECP5-5G sysCONFIG User Guide.
- Raspberry Pi HAT+ Specification.
- Raspberry Pi 40-pin GPIO documentation.
- Numato Mimas ECP5 Mini schematic/GPIO reference, exact same `LFE5U-45F-7BG256I`, used only as a cross-check.
