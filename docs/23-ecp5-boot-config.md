# Rev.0 ECP5 device, SPI flash and configuration architecture

## Decision

Rev.0 freezes the physical FPGA as:

```text
Lattice LFE5U-45F-7BG256I
ECP5, plain LFE5U (no SERDES)
44k logic-cell class
BG256 / caBGA256
14 x 14 mm
0.8 mm pitch
industrial grade
speed grade -7
```

This device is intentionally larger than the historical XC3S1400AN in physical capacity, but the `release_reference` build remains constrained by `rtl/resource_budget.json` to the historical resource envelope.

The -7 speed grade is sufficient for the 25 MHz -> 125 MHz reference clock plan. Rev.0 does not depend on -8 timing and therefore does not make the faster, less available speed grade a BOM requirement.

The exact FPGA OPN must still be rechecked for distributor stock at procurement time because ECP5 BG256 supply is materially tighter than most of the analog BOM.

## Configuration flash

Preferred Rev.0 SPI NOR:

```text
Winbond W25Q64JVSSIQ
64 Mbit
2.7 ... 3.6 V
SPI / Dual / Quad capable
133 MHz maximum device clock
-40 ... +85 degC
SOIC-8 208 mil
```

The reference PCB uses it as a conventional 3.3 V serial SPI configuration memory.

Reasons for 64 Mbit rather than minimum capacity:

- the LFE5U-45F maximum uncompressed image including initialized EBR is about 9.74 Mbit;
- Lattice recommends at least 16 Mbit for one maximum-size 45-class image;
- Lattice gives 32 Mbit as the minimum flash density for dual boot on a 45-class ECP5;
- 64 Mbit therefore gives generous margin for a golden image plus an update image without relying on compression;
- the SOIC-8 package is easy to inspect, rework and probe;
- the device is inexpensive and widely stocked.

The extra flash capacity is not part of the FPGA runtime resource budget.

## Boot policy

Reference boot mode:

```text
ECP5 Master SPI
single-bit SPI boot is sufficient
```

Quad-SPI boot is not required for Rev.0. Configuration speed is not performance-critical for a DCF77 receiver, while a conventional single-bit boot is simpler to validate and reduces dependence on flash status-register / quad-enable behavior.

The board may preserve D2/D3 routing options if pin planning makes that convenient, but the reference boot path must succeed using only:

```text
MCLK
CSSPIN
D0 / MOSI
D1 / MISO
```

## Configuration mode straps

Lattice defines Master SPI with:

```text
CFGMDN[2:0] = 0 1 0
```

Rev.0 hard-straps the mode rather than using a DIP switch:

```text
CFG2 -> GND
CFG1 -> 4.7 kOhm -> VCCIO8
CFG0 -> GND
```

Use fixed resistors because the receiver does not need user-selectable configuration modes in normal operation.

JTAG remains available independently for development/recovery.

## Configuration status/control pins

Use the current Lattice hardware-checklist recommendations:

```text
PROGRAMN -> 4.7 kOhm pull-up to VCCIO8
INITN    -> 4.7 kOhm pull-up to VCCIO8
DONE     -> 4.7 kOhm pull-up to VCCIO8
CSSPIN   -> 4.7 kOhm pull-up to VCCIO8
MCLK     -> 1 kOhm pull-up to VCCIO8
```

`PROGRAMN`, `INITN` and `DONE` must also be accessible at test points.

Provide a local pushbutton or clearly accessible test pad that can assert `PROGRAMN` low for manual reconfiguration. If a host-controlled transistor is later added, it must be open-drain/open-collector so it cannot drive against the FPGA pull-up domain.

`DONE` is the definitive indication that the FPGA has entered user mode. Do not use an arbitrary delay after power-on as a substitute for checking configuration completion.

## SPI flash wiring

Reference topology:

```text
3V3_D / VCCIO8
    |
    +---- W25Q64JV VCC
    |
   100 nF
    |
   GND

ECP5 MCLK --------> W25Q64 CLK
ECP5 CSSPIN ------> W25Q64 /CS
ECP5 D0/MOSI -----> W25Q64 DI / IO0
ECP5 D1/MISO <----- W25Q64 DO / IO1
```

The flash must be physically close to ECP5 bank 8.

Use short traces and avoid routing configuration clocks toward the ferrite/AFE region.

Add footprints for small series damping resistors on MCLK and MOSI if signal-integrity review indicates they are useful. Reference initial population can be 0 ohm; the values are not RF tuning components and do not affect the no-trim analog policy.

## Flash WP/HOLD pins

For the SOIC-8 W25Q64JV:

```text
/IO2/WP
/IO3/HOLD
```

are not required in single-bit reference boot mode.

Tie them to 3.3 V with individual 10 kOhm pull-ups so the flash stays in the normal serial-SPI state and is not accidentally write-protected or held.

Do not leave these pins floating.

## Dual-boot policy

The 64 Mbit flash is intentionally large enough for dual boot.

Reference flash map concept:

```text
0x000000 ...  golden/recovery image
next region ... release/update image
remaining     reserved
```

The first manufactured boards may initially program only one image while the dual-boot/update flow is being verified.

A future field-update mechanism must never erase the golden recovery image as part of an ordinary update.

Dual boot is a reliability feature, not a license to use extra ECP5 runtime resources; both images must still satisfy the appropriate FPGA resource profile.

## JTAG recovery

JTAG is mandatory on both PCB variants even though normal boot comes from SPI flash.

Lattice's current recommendations are:

```text
TDI -> 4.7 kOhm pull-up to VCCIO8
TMS -> 4.7 kOhm pull-up to VCCIO8
TDO -> 4.7 kOhm pull-up to VCCIO8
TCK -> 4.7 kOhm pull-down to GND
```

Expose at least:

```text
TCK
TMS
TDI
TDO
VCCIO8 reference
GND
```

on a compact keyed debug connector or Tag-Connect-compatible footprint.

The same interface must be present on HAT+ and standalone variants so neither board can become unrecoverable because its host interface is unavailable.

## Power sequencing

The current Lattice hardware checklist recommends powering VCCIO supplies before or together with VCC and VCCAUX.

The existing Rev.0 architecture therefore remains appropriate:

```text
5V_SYS
  |
  +--> 3V3_D first
  |      -> VCCIO8
  |      -> W25Q64JV flash
  |      -> configuration pull-ups
  |
  +--> after 3V3_D power-good
         +--> 1V1_CORE / VCC
         +--> 2V5_AUX / VCCAUX
```

The ECP5 POR monitors VCC, VCCAUX and VCCIO8 and waits until all monitored rails have crossed their thresholds before initialization proceeds.

All rails must ramp monotonically.

The board must not intentionally pulse PROGRAMN low while the FPGA is still in the initialization phase.

## VCCIO bank policy

Use:

```text
VCCIO8 = 3V3_D
```

because bank 8 contains configuration/JTAG functions and the selected flash is a 3.3 V device.

Other ECP5 I/O banks are assigned according to interfaces:

- ADC serial interface: 3.3 V-compatible bank unless later level constraints require otherwise;
- TCXO input: 3.3 V LVCMOS-capable bank;
- LCD / host SPI / PPS: prefer 3.3 V banks for interface simplicity;
- no SERDES supplies are required because the selected device is plain `LFE5U`.

The final bank assignment is frozen only after the authoritative Lattice `LFE5U-45` BG256 pinout is imported into the tscircuit part wrapper.

## Decoupling policy

Follow the ECP5 hardware checklist and selected regulator transient analysis rather than using one capacitor value everywhere.

At minimum the schematic must provide distributed local decoupling for:

```text
1V1_CORE / VCC
2V5_AUX  / VCCAUX
3V3_D     / VCCIO banks
```

with bulk capacitance near each rail source and small MLCCs distributed around the BGA power pins.

The exact capacitor count/values will be frozen with the BG256 power-pin map and PDN review before routing.

## Placement constraints for Quilter

Hard constraints:

- ECP5 and W25Q64JV form one compact digital cluster;
- flash is adjacent to the relevant bank-8 configuration pins;
- MCLK/CSSPIN/MOSI/MISO remain short and do not cross the analog partition;
- JTAG header/test footprint stays reachable at the board edge;
- PROGRAMN/INITN/DONE test points remain probe-accessible;
- no ECP5/flash fast trace passes under the ferrite or OPA810 input network;
- buck converter hot loops remain on the opposite/noisy side of the ECP5 from the AFE where possible.

## Sourcing snapshot

September 2026 snapshot:

```text
LFE5U-45F-7BG256I
  active
  industrial
  immediate stock small / long factory lead time

W25Q64JVSSIQ
  active at Digi-Key
  >10k immediate Digi-Key stock observed
```

The FPGA is currently one of the tighter-supply parts in the whole BOM, so procurement availability must be checked early rather than after layout release.

If `-7BG256I` becomes unavailable, a pin-compatible BG256 speed-grade substitution may be considered only after timing and temperature-grade review. Do not silently change to a commercial-temperature device.

## References

- Lattice ECP5/ECP5-5G Family Data Sheet.
- Lattice ECP5/ECP5-5G Hardware Checklist, FPGA-TN-02038.
- Lattice ECP5/ECP5-5G sysCONFIG User Guide, FPGA-TN-02039.
- Lattice Dual Boot and Multiple Boot technical note.
- Lattice LFE5U-45 BG256 official pinout/migration files.
- Winbond W25Q64JV product documentation.
- September 2026 Digi-Key/Mouser availability snapshots.
