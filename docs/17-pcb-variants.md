# PCB variants: Raspberry Pi HAT+ and standalone USB-C

## Decision

The receiver will be built as **two PCB variants sharing one electrical receiver core**:

1. **Raspberry Pi HAT+ variant** — powered from the Raspberry Pi 40-pin header;
2. **standalone variant** — powered from USB-C.

The two boards must share the same analog front end, ADC interface, clock architecture, ECP5 core and receiver RTL wherever physically possible.

The objective is not to maintain two unrelated designs. The objective is to maintain one receiver core with two host/power shells.

```text
                         +-----------------------------+
                         | COMMON DCF77 RECEIVER CORE  |
                         |                             |
antenna -> AFE -> PGA -> ADC -> ECP5 -> timing/decoder
                         |          |
                         |          +-> clock/DCTCXO
                         |          +-> SPI/debug
                         +-------------+---------------+
                                       |
                       +---------------+---------------+
                       |                               |
                Raspberry Pi HAT+               standalone USB-C
                5V from 40-pin GPIO              5V from Type-C
                Pi host interface                local/debug host
```

## Common internal power boundary

Both variants should present the same internal power interface to the receiver core:

```text
5V_SYS
  -> protected/filtered power tree
  -> FPGA core rail
  -> FPGA auxiliary rail
  -> FPGA I/O rails
  -> ADC rails
  -> analog rails
  -> clock rail
```

Everything after `5V_SYS` should be shared in tscircuit unless a measured EMI/noise requirement forces a variant-specific change.

This gives a very useful validation property: differences in receiver performance between the HAT+ and standalone boards can be attributed primarily to host/power environment rather than different AFE/ADC/FPGA circuits.

# Variant A — Raspberry Pi HAT+

## HAT+ standard

Use the current Raspberry Pi **HAT+** specification, not the deprecated original HAT specification.

The board uses the standard 40-pin 2.54 mm Raspberry Pi GPIO connector. Raspberry Pi documents two 5 V pins, two 3.3 V pins, ground pins and 3.3 V GPIO signals on this header.

The receiver is a **Standard HAT+ that consumes power from the Raspberry Pi**. It is not a Power HAT+: it does not source 5 V back into the Raspberry Pi.

## Power strategy

Primary input:

```text
Raspberry Pi 5V pins
       |
       v
input protection / load switch
       |
       v
5V_SYS
       |
       v
shared receiver power tree
```

Do **not** use the Raspberry Pi 3.3 V rail as the main source for FPGA/ADC/analog loads. Generate the receiver rails locally from the 5 V input.

Reasons:

- lower dependency on Raspberry Pi regulator loading;
- identical downstream power tree to the standalone variant;
- easier RF/noise comparison;
- cleaner lifecycle isolation;
- simpler handling of future Raspberry Pi revisions.

## HAT+ STANDBY behaviour

Current HAT+ requirements explicitly account for Raspberry Pi `STANDBY`, where the 5 V header rail remains powered but the 3.3 V rail is off.

The preferred receiver implementation is therefore:

```text
PI_5V -----------------------> input load switch ---> 5V_SYS

PI_3V3 ---> presence/enable logic ------------------^ ENABLE
```

Thus:

- Pi active / 3.3 V present -> receiver core powered;
- Pi standby / only 5 V present -> receiver core off;
- no FPGA output can back-power an unpowered Raspberry Pi GPIO bank.

The exact load switch/supervisor is still to be selected.

A hardware option may permit `ALWAYS_ON` operation for receiver experiments, but normal HAT+ behaviour should track Raspberry Pi active power state.

## HAT EEPROM

Reserve the HAT+ identification EEPROM/interface required by the current HAT+ specification.

The identification interface uses the reserved ID pins rather than the receiver host-data bus. Keep HAT identification separate from normal runtime receiver communication.

## Raspberry Pi host interface

The preferred runtime connection between Raspberry Pi and ECP5 is intentionally narrow:

```text
SPI host link
interrupt / data-ready
optional reset
optional PPS / timing input-output
```

Do not consume a large parallel GPIO bus unless measurements prove SPI inadequate.

A buffered/FIFO-based SPI interface should be sufficient for normal decoded time, status and diagnostic data. Raw 930 kS/s ADC streaming requires roughly 15 Mbit/s at 16 bits/sample before framing and should be treated as a deliberate high-rate diagnostic mode, not assumed to fit every Linux SPI configuration without benchmarking.

Exact Raspberry Pi GPIO assignments are not frozen yet.

## Power budget gate

Before HAT+ PCB release, measure/estimate:

```text
ECP5 worst-case active consumption
ADC consumption
analog front-end consumption
clock consumption
regulator losses
startup/inrush current
```

Design goal for the reference receiver is to keep HAT consumption modest enough to coexist with a normally powered Raspberry Pi without requiring a special high-power architecture.

The actual current limit must be derived from the target Raspberry Pi model and PSU combination, not guessed from the existence of 5 V pins.

## HAT-specific EMI concerns

The Raspberry Pi is a very noisy neighbour for a 77.5 kHz weak-signal receiver.

The HAT+ PCB therefore needs stricter floorplanning than the standalone board:

- ferrite antenna should preferably be remote from the Pi rather than directly above the SoC/PMIC;
- keep the AFE at the board edge farthest from the Raspberry Pi digital core;
- prevent Pi switching-current return paths from crossing the analog region;
- filter the incoming Pi 5 V before the receiver power tree;
- evaluate common-mode current through mounting hardware/shields/cables;
- benchmark reception with Pi CPU/USB/Wi-Fi/Ethernet activity enabled and disabled.

A short cable to a remote ferrite antenna may be preferable to mounting the ferrite directly on top of the Pi.

# Variant B — standalone USB-C

## Power role

The standalone board is a USB Type-C **sink**, not a source.

Baseline architecture:

```text
USB-C receptacle
       |
       v
CC / sink detection
       |
       v
VBUS protection + controlled load switch/eFuse
       |
       v
5V_SYS
       |
       v
shared receiver power tree
```

The baseline board does not require USB Power Delivery if measured peak power remains within ordinary 5 V Type-C capability.

Do not add USB-PD simply because the connector is USB-C. Add PD only if the measured system power budget or another real requirement needs a negotiated voltage/current profile.

## Why not only two 5.1 kOhm resistors?

A minimal 5 V sink can advertise `Rd` on CC1/CC2. However the receiver will have significant downstream bulk/decoupling capacitance.

The USB-C power implementation should therefore include controlled connection of the downstream capacitance through a power-path/load-switch/eFuse solution rather than connecting a large receiver power tree directly to VBUS.

The exact Type-C controller/eFuse is still open and will be selected using the same lifecycle/availability policy as the oscillator and ADC.

## USB data

The standalone USB-C connector may also carry USB 2.0 data, but **power and data are separate architectural decisions**.

Possible Rev.0 choices:

1. USB-C power only + separate debug/UART/JTAG connector;
2. USB-C power + USB 2.0 bridge to FPGA/debug logic.

Do not make the receiver core dependent on a specific USB bridge. The host boundary remains an abstract transport interface.

## Standalone controls/output

The standalone variant should be usable without a Raspberry Pi.

Reserve interfaces for at least:

- PPS output;
- status/lock indicators;
- JTAG/programming;
- serial/debug host link;
- optional display or front-panel connector;
- optional external trigger/time-reference input.

# Shared tscircuit structure

The tscircuit source should make the split explicit:

```text
hardware/tscircuit/
  src/
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      receiver_power.tsx

    variants/
      raspberry_pi_hatplus.tsx
      standalone_usb_c.tsx

    host/
      rpi_spi.tsx
      usb_debug.tsx

    power/
      hat_5v_input.tsx
      usb_c_5v_input.tsx

    board/
      common_constraints.ts
      hatplus_constraints.ts
      standalone_constraints.ts
      quilter.ts
```

The common receiver block consumes `5V_SYS` and a small generic host interface. It should not know whether that 5 V originated from a Raspberry Pi or USB-C connector.

# Quilter workflow for both variants

Each PCB gets a separate Quilter job because mechanical geometry and noise environment differ.

```text
tscircuit common core + HAT+ shell
  -> KiCad HAT+ pre-Quilter
  -> HAT-specific placement regions/keepouts
  -> Quilter
  -> reviewed HAT+ KiCad


tscircuit common core + USB-C shell
  -> KiCad standalone pre-Quilter
  -> standalone placement regions/keepouts
  -> Quilter
  -> reviewed standalone KiCad
```

Do not attempt to force identical coordinates between the two boards. Preserve **electrical topology and RF intent**, not arbitrary XY positions.

# Validation matrix

The two-board strategy is useful scientifically as well as mechanically.

Run the same receiver tests on both variants:

| Test | HAT+ | standalone |
|---|---:|---:|
| analog noise floor | measure | measure |
| 77.5 kHz self-spur | measure | measure |
| carrier phase noise | measure | measure |
| AM detection | same regression | same regression |
| PM correlation | same regression | same regression |
| clock discipline | same RTL | same RTL |
| sensitivity | compare | baseline |
| timing offset | calibrate | calibrate |

The standalone board is likely to become the cleaner RF reference. The HAT+ board can then be judged by how close it remains to that reference when attached to an active Raspberry Pi.

# Current design policy

```text
ONE receiver architecture
TWO PCB/power/host variants

Variant A: Raspberry Pi Standard HAT+
           powered from Raspberry Pi 5 V

Variant B: standalone
           powered from USB-C 5 V sink
```

The core AFE/ADC/ECP5/clock/RTL should remain shared unless measurements prove a variant-specific change is necessary.

## External specifications used

- Raspberry Pi HAT+ Specification, current HAT+ standard.
- Raspberry Pi GPIO/40-pin documentation.
- USB Type-C sink implementation guidance; final port-controller design will be based on the selected component's current data sheet and USB-C requirements.
