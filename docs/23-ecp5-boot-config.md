# Rev.0 ECP5 device, SPI flash and configuration architecture

## Decision

Rev.0 physical FPGA:

```text
Lattice LFE5U-45F-7BG256I
plain ECP5 / no SERDES
BG256 caBGA, 14 x 14 mm, 0.8 mm pitch
industrial temperature grade
speed grade -7
```

The physical 45F gives development headroom, but `release_reference` remains constrained by `rtl/resource_budget.json` to the historical XC3S1400AN resource envelope.

The complete user-I/O pin allocation is now frozen separately in [`27-ecp5-pin-plan-hat.md`](27-ecp5-pin-plan-hat.md) and mirrored in `hardware/tscircuit/pin-plan.json`.

## Configuration flash

Reference SPI NOR:

```text
Winbond W25Q64JVSSIQ
64 Mbit
2.7 ... 3.6 V
SOIC-8 208 mil
-40 ... +85 degC
```

64 Mbit gives enough room for a golden/recovery image plus an update image without relying on bitstream compression.

## Boot mode

Reference boot:

```text
ECP5 Master SPI
single-bit serial mode
CFGMDN[2:0] = 010
```

Quad-SPI is not required for Rev.0. Configuration time is not performance-critical for a DCF77 receiver, while serial Master SPI is simpler and easier to recover/debug.

## Exact BG256 Bank-8 ball map

For `LFE5U-45F-7BG256I`:

```text
D7/IO7                    T6
D6/IO6                    R6
D5/MISO2/IO5              R7
D4/MOSI2/IO4              P7
D3/IO3                    N7
D2/IO2                    M7
D1/MISO/IO1               T7
D0/MOSI/IO0               T8
CSN/SN                    R8
CS1N                      P8
HOLDN/DI/BUSY/CSSPIN/CEN  N8
DOUT/CSON                 M8
WRITEN                    M9
MCLK/CCLK/SCK             N9
INITN                     T9
PROGRAMN                  R9
DONE                      P9
CFG1                      P10
CFG2                      R10
CFG0                      N10
TDO                       M10
TCK                       T10
TDI                       R11
TMS                       T11
VCCIO8                    L6
```

These names/balls are checked against the exact-device BG256 pin map. The tscircuit symbol must still be compared mechanically against the current Lattice `FPGA-SC-02034` CSV before fabrication.

## Single-bit Master-SPI wiring

Reference connection:

```text
ECP5 N8  CSSPIN   ------> W25Q64 /CS
ECP5 N9  MCLK     ------> W25Q64 CLK
ECP5 T8  D0/MOSI  ------> W25Q64 DI / IO0
ECP5 T7  D1/MISO  <------ W25Q64 DO / IO1
```

Flash-side pins not used for serial boot:

```text
W25Q64 /WP   -> 10 kOhm pull-up to 3V3_D
W25Q64 /HOLD -> 10 kOhm pull-up to 3V3_D
```

ECP5 Master-SPI pull policy from the current Lattice sysCONFIG guidance:

```text
MOSI T8   -> 10 kOhm pull-up to VCCIO8
MISO T7   -> 10 kOhm pull-up to VCCIO8
CSSPIN N8 -> 4.7 kOhm pull-up to VCCIO8
MCLK N9   -> 1 kOhm pull-up to VCCIO8
```

`D2/D3` are not required for the single-bit reference path and are not routed to the flash in Rev.0.

`DOUT/CSON` is not required to boot a single FPGA from the local flash; keep it available only as required by the final symbol/configuration rules and do not create a long unused trace.

## Configuration mode straps

Hard strap Master SPI:

```text
CFG2 R10 -> GND
CFG1 P10 -> 4.7 kOhm -> VCCIO8
CFG0 N10 -> GND
```

There is no user DIP switch for configuration mode.

## Configuration control/status

Use:

```text
PROGRAMN R9 -> 4.7 kOhm pull-up to VCCIO8
INITN    T9 -> 4.7 kOhm pull-up to VCCIO8
DONE     P9 -> 4.7 kOhm pull-up to VCCIO8
```

Expose `PROGRAMN`, `INITN` and `DONE` as probe-accessible test points.

Provide a local pushbutton or test pad capable of asserting `PROGRAMN` low. Any host-controlled reset/reconfigure transistor must be open-drain/open-collector.

`DONE` is the definitive configuration-complete indication; do not substitute an arbitrary startup delay.

## JTAG recovery

JTAG remains mandatory on both PCB variants.

Exact balls:

```text
TDO M10
TCK T10
TDI R11
TMS T11
```

Reference pulls:

```text
TDI -> 4.7 kOhm pull-up to VCCIO8
TMS -> 4.7 kOhm pull-up to VCCIO8
TDO -> 4.7 kOhm pull-up to VCCIO8
TCK -> 4.7 kOhm pull-down to GND
```

Expose:

```text
TCK
TMS
TDI
TDO
VCCIO8 reference
GND
PROGRAMN preferred
```

on the same keyed debug/Tag-Connect-compatible interface for both boards.

## Bank-8 power source

```text
VCCIO8 = 3V3_D
```

Source differs by variant:

```text
standalone: 5V_SYS -> local 3.3 V buck -> 3V3_D
HAT+:       PI_3V3 --------------------> 3V3_D
```

The W25Q64 and configuration pull-ups use the same rail, so no level translation exists inside the boot island.

## Power sequencing

Reference sequence:

```text
3V3_D valid first
   -> VCCIO8 valid
   -> W25Q64 valid
   -> configuration pulls valid
   -> enable 1V1_CORE and 2V5_AUX
   -> ECP5 POR completes
   -> Master SPI boot
```

On the HAT+, `3V3_D` is Pi 3.3 V and naturally disappears in HAT+ STANDBY. The remaining local receiver rails are disabled when Pi 3.3 V is absent, preventing GPIO back-powering.

All ECP5 rails must ramp monotonically.

## Dual-boot policy

Reference flash-map concept:

```text
low address      golden/recovery image
next region      release/update image
remaining space  reserved
```

The first manufactured boards may initially program only one image while update/recovery logic is verified.

Normal field updates must never erase the golden image.

Both golden and release receiver builds remain subject to their appropriate FPGA resource profile; extra flash capacity does not relax the historical runtime resource budget.

## Placement constraints

The ECP5 + W25Q64 + JTAG/configuration block is one compact digital cluster.

Hard rules:

- flash adjacent to Bank 8;
- `MCLK/CSSPIN/MOSI/MISO` short and local;
- no configuration clock route toward the ferrite/OPA810/LTC1562 region;
- JTAG footprint reachable from board edge;
- `PROGRAMN/INITN/DONE` probe-accessible;
- no decorative routing on unused Bank-8 configuration pins.

## References

- Lattice ECP5U-45 Pinout, `FPGA-SC-02034`.
- Lattice ECP5/ECP5-5G sysCONFIG User Guide, `FPGA-TN-02039`.
- Lattice ECP5/ECP5-5G Hardware Checklist, `FPGA-TN-02038`.
- Lattice Dual Boot and Multiple Boot technical note.
- Winbond W25Q64JV documentation.
