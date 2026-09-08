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

The board is now Raspberry Pi HAT+ only. There is no standalone USB-C configuration/power variant.

The complete user-I/O allocation is frozen in [`27-ecp5-pin-plan-hat.md`](27-ecp5-pin-plan-hat.md) and mirrored in `hardware/tscircuit/pin-plan.json`.

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

```text
ECP5 Master SPI
single-bit serial mode
CFGMDN[2:0] = 010
```

Quad-SPI is not required for Rev.0.

## Exact BG256 Bank-8 ball map

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

These names/balls must be checked against the current Lattice `FPGA-SC-02034` source before fabrication.

## Single-bit Master-SPI wiring

```text
ECP5 N8  CSSPIN   ------> W25Q64 /CS
ECP5 N9  MCLK     ------> W25Q64 CLK
ECP5 T8  D0/MOSI  ------> W25Q64 DI / IO0
ECP5 T7  D1/MISO  <------ W25Q64 DO / IO1
```

Flash-side unused serial pins:

```text
W25Q64 /WP   -> 10 kOhm pull-up to 3V3_D
W25Q64 /HOLD -> 10 kOhm pull-up to 3V3_D
```

ECP5 Master-SPI pulls:

```text
MOSI T8   -> 10 kOhm pull-up to VCCIO8
MISO T7   -> 10 kOhm pull-up to VCCIO8
CSSPIN N8 -> 4.7 kOhm pull-up to VCCIO8
MCLK N9   -> 1 kOhm pull-up to VCCIO8
```

`D2/D3` are not required for the reference boot path.

## Configuration straps

```text
CFG2 R10 -> GND
CFG1 P10 -> 4.7 kOhm -> VCCIO8
CFG0 N10 -> GND
```

There is no user configuration-mode switch.

## Configuration status/control

```text
PROGRAMN R9 -> 4.7 kOhm pull-up to VCCIO8
INITN    T9 -> 4.7 kOhm pull-up to VCCIO8
DONE     P9 -> 4.7 kOhm pull-up to VCCIO8
```

Expose `PROGRAMN`, `INITN` and `DONE` as test points. Provide a manual pad/button capable of asserting `PROGRAMN` low. Any host reset path must be open-drain/open-collector.

## JTAG recovery

JTAG is mandatory on the HAT+ even though normal boot is from SPI flash.

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

Expose `TCK`, `TMS`, `TDI`, `TDO`, `3V3_D` reference, GND and preferably `PROGRAMN` on a keyed debug/Tag-Connect-compatible interface.

## Bank-8 power source

```text
VCCIO8 = 3V3_D = PI_3V3
```

The W25Q64 and all configuration pull-ups share this Pi-supplied 3.3 V digital domain. No level translation is required.

## Power sequencing

Reference HAT sequence:

```text
PI_3V3 valid first
   -> 3V3_D / VCCIO8 valid
   -> W25Q64 valid
   -> configuration pulls valid
   -> 2V5_AUX starts
   -> PI_3V3 enables TPS22975N
   -> 5V_SYS rises
   -> 1V1_CORE starts
   -> ECP5 internal POR completes
   -> Master SPI boot
```

In HAT+ STANDBY, Pi 3.3 V disappears and the local 5 V receiver path is also switched off, preventing GPIO back-powering.

All ECP5 rails must ramp monotonically.

## Dual-boot policy

Reference flash map concept:

```text
low address      golden/recovery image
next region      release/update image
remaining space  reserved
```

Normal field updates must never erase the golden image. Both images remain subject to the appropriate FPGA resource profile.

## Placement constraints

The ECP5 + W25Q64 + JTAG/configuration block is one compact digital cluster.

Hard rules:

- flash adjacent to Bank 8;
- `MCLK/CSSPIN/MOSI/MISO` short and local;
- no configuration clock route toward ferrite/OPA810/LTC1562;
- JTAG footprint reachable from board edge;
- `PROGRAMN/INITN/DONE` probe-accessible;
- no decorative routing on unused Bank-8 configuration pins.

## References

- Lattice ECP5U-45 Pinout, `FPGA-SC-02034`.
- Lattice ECP5/ECP5-5G sysCONFIG User Guide, `FPGA-TN-02039`.
- Lattice ECP5/ECP5-5G Hardware Checklist, `FPGA-TN-02038`.
- Lattice Dual Boot and Multiple Boot technical note.
- Winbond W25Q64JV documentation.
