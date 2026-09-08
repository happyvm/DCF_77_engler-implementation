# Standalone USB-C power input

## Decision

The standalone Rev.0 board uses USB-C as a 5 V sink without USB Power Delivery.

Reference input chain:

```text
GCT USB4105-GF-A receptacle
    |
    +--> CC1/CC2 -> TUSB320LAIRWBR
    |
    +--> VBUS -> TPS259470ARPWR eFuse -> 5V_SYS
    |
    +--> USB2 D+/D- reserved for optional future debug/data path
```

No negotiated voltage above 5 V is required for the reference receiver.

## USB-C receptacle

Preferred connector:

```text
GCT USB4105-GF-A
USB Type-C receptacle
USB 2.0 contact set
right-angle SMT with through-hole shell tabs
5 A connector rating
-40 ... +85 degC
```

The connector is active and extremely well stocked.

Mechanical shell tabs are valuable for a lab instrument that may see repeated cable insertion.

## Type-C CC controller

Preferred controller:

```text
Texas Instruments TUSB320LAIRWBR
USB Type-C CC logic/port controller
UFP / sink mode
-40 ... +85 degC
```

Configure the `PORT` pin low so the board is permanently a UFP/sink.

In UFP mode the controller presents the required Rd behavior on both CC pins and detects:

- attach/detach;
- cable orientation;
- advertised Type-C current level;
- VBUS presence.

Rev.0 does not need to change roles and never sources VBUS.

Use GPIO mode unless the final host-control design gains a concrete benefit from I2C.

The current-mode outputs can be routed to ECP5 GPIO so firmware/RTL can distinguish default / 1.5 A / 3 A Type-C current advertisements and suppress nonessential loads when supply capability is limited.

## Why use a CC controller instead of only two resistors

A pure 5 V sink can be implemented with discrete Rd resistors, but the TUSB320 gives useful deterministic information at very low BOM cost:

- attach state;
- source current advertisement;
- orientation/debug visibility;
- proper dead-battery UFP behavior;
- an explicit Type-C state machine rather than assumptions in firmware.

It does not add USB-PD complexity.

## Controlled VBUS power path

Preferred eFuse:

```text
Texas Instruments TPS259470ARPWR
2.7 ... 23 V input
integrated back-to-back FETs
true reverse-current blocking
adjustable current limit
adjustable soft start
short-circuit / thermal protection
power-good / fault functions
```

The part is active and very well stocked.

Reference topology:

```text
USB-C VBUS
   |
   +--> small input capacitance / TVS as required
   |
TPS259470A
   |
   +--> controlled slew / inrush
   +--> reverse blocking
   +--> current limit
   |
  5V_SYS
```

The large downstream receiver capacitance therefore sits behind the controlled power path rather than directly on USB VBUS.

## Current policy

The reference receiver must be designed to operate in its essential receive mode from ordinary USB-C default power without assuming 1.5 A or 3 A advertisement.

Nonessential loads include:

- LCD backlight;
- high-power debug interfaces;
- future external accessory power.

These may be disabled when the TUSB320 reports only default current capability.

The final TPS259470A current-limit resistor and soft-start capacitor will be calculated from the finalized worst-case board power budget; these are deterministic design values, not per-board trims.

## Input protection

Provide:

- low-capacitance ESD protection for CC1/CC2;
- USB-rated ESD protection for D+/D- if data is populated;
- appropriately rated VBUS TVS protection;
- shield connection strategy that does not dump cable currents through the ferrite/AFE return region.

The connector shield should meet chassis/EMI intent through a controlled connection network rather than an arbitrary long trace into analog ground.

## USB data

USB 2.0 data is optional in Rev.0.

The connector is selected with USB2 contacts so future debug/data can use the same physical port, but the receiver core must not depend on a USB bridge for operation.

If USB data hardware is not populated:

```text
D+ / D- remain local to connector protection/test area
```

and must not become long unterminated traces across the board.

## RF/placement constraints

This block is electrically noisy compared with the ferrite input.

Hard rules for Quilter:

- USB-C connector at board edge;
- TUSB320 and CC protection immediately behind connector;
- TPS259470A and VBUS protection immediately behind connector/power region;
- keep VBUS/high-current 5V_SYS entry currents away from the AFE return path;
- do not route USB D+/D- or CC lines through the ferrite region;
- keep connector shield return geometry away from ANT_IN and OPA810;
- place the standalone power block on the digital/noisy side of the PCB.

## Relationship to HAT+ board

Only the source of `5V_SYS` differs.

```text
standalone:
USB-C -> Type-C/eFuse -> 5V_SYS

HAT+:
Pi 5 V -> HAT input protection/gating -> 5V_SYS
```

Everything downstream of `5V_SYS` remains the same receiver power tree.

## Sourcing snapshot

September 2026 checks:

```text
USB4105-GF-A       active, >100k Digi-Key stock
TUSB320LAIRWBR     active, >10k Digi-Key stock
TPS259470ARPWR     active, >60k Digi-Key stock
```

These are unusually healthy sourcing levels compared with the ECP5 itself.

## References

- USB Type-C requirements relevant to UFP/sink operation.
- TI TUSB320LAI data sheet.
- TI TPS25947 data sheet.
- GCT USB4105 connector documentation.
- September 2026 Digi-Key availability snapshots.
