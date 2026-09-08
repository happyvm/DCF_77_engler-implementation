# tscircuit hardware workspace

This directory is the authoritative source for DCF77 receiver schematic and PCB design intent.

The project produces **two PCB variants from one shared receiver core**:

1. Raspberry Pi Standard HAT+ — powered from the Raspberry Pi 5 V GPIO-header rail;
2. standalone board — powered from USB-C as a 5 V sink.

The analog front end, ADC, clock, ECP5, display/timing outputs and downstream receiver power tree should remain shared wherever possible.

## Current pin-level decisions

Now selected for Rev.0:

```text
FPGA        Lattice ECP5 LFE5U-45F, BG256 preferred
ADC         LTC1407AIMSE-1#PBF
ADC rate    930 kS/s
ADC driver  OPA2810IDR candidate, validation required
PGA         LTC6912 family, -1 still preferred unless sourcing changes
PPS         mandatory dedicated ECP5 hardware output
Display     transflective 20x2 LCD on both PCB variants
```

Still open before the complete `index.circuit.tsx` is frozen:

- sustainable high-impedance antenna input stage;
- exact antenna part/tuning network from measured L/Q;
- final LTC6912 OPN/package;
- regulator tree;
- exact ECP5 speed/temperature OPN;
- SPI configuration flash;
- final fixed TCXO OPN/frequency;
- exact LCD OPN/mechanical arrangement;
- USB-C sink/power-path controller;
- Raspberry Pi GPIO assignments.

ADC details are in [`../../docs/18-adc-selection.md`](../../docs/18-adc-selection.md).

## Planned structure

```text
hardware/tscircuit/
  package.json
  tsconfig.json

  src/
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      display.tsx
      pps.tsx
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

    parts/
      ... reusable symbols/footprints/part wrappers ...

    board/
      common_constraints.ts
      hatplus_constraints.ts
      standalone_constraints.ts
      quilter.ts

  dist/
    hatplus/
      circuit-json/
      kicad-pre-quilter/
      kicad-post-quilter/
      fabrication/

    standalone/
      circuit-json/
      kicad-pre-quilter/
      kicad-post-quilter/
      fabrication/
```

## Tooling policy

- **tscircuit TSX is the editable hardware source of truth.**
- Pin-accurate manufacturer data must be checked before part wrappers are committed.
- RF/mechanical hard placement constraints are encoded before automated layout.
- **Quilter is the selected placement/routing engine.**
- Each variant is exported from tscircuit to KiCad and submitted to a separate Quilter job with its own mechanical and RF constraints.
- Quilter returns native KiCad candidates for engineering review.
- A Quilter result is not fabrication-ready merely because it is routed or DRC-clean.
- Final KiCad inspection/DRC and Gerber review are mandatory before fabrication.
- Electrical/footprint/mandatory-placement changes discovered during KiCad/Quilter review must be represented back in tscircuit for the next iteration.

See [`../../docs/14-hardware-cad-tscircuit.md`](../../docs/14-hardware-cad-tscircuit.md) and [`../../docs/17-pcb-variants.md`](../../docs/17-pcb-variants.md).

## Shared power boundary

Both boards present the same internal interface to the common receiver core:

```text
5V_SYS
  -> receiver regulators / filters
  -> AFE/PGA/ADC driver
  -> dedicated low-noise ADC rail
  -> clock
  -> ECP5 rails
  -> LCD/backlight rail
```

Only the 5 V input shell differs:

```text
HAT+:
Raspberry Pi 5V -> protected/gated input -> 5V_SYS

standalone:
USB-C VBUS -> Type-C sink/power path -> 5V_SYS
```

The HAT+ variant uses Raspberry Pi 3.3 V only for HAT identification / power-state sensing as required, not as the main FPGA/analog supply.

## RF-critical placement policy

The following are not freely placed by Quilter:

- antenna mechanical interface;
- first high-impedance input device;
- critical antenna tuning components;
- ADC and its local analog driver/input RC network as a tightly constrained cluster;
- TCXO and its clock escape direction;
- mounting holes;
- mechanically fixed board-edge connectors.

Analog, ADC, clock, FPGA, LCD, USB/debug and power blocks receive placement regions/keepouts so Quilter optimizes within the intended RF floorplan rather than inventing the floorplan itself.

The HAT+ and standalone boards have different interference environments, so their placement constraints are variant-specific even though the receiver topology is shared.

## Raspberry Pi HAT+ variant

- follow the current HAT+ specification;
- powered from Raspberry Pi 5 V header pins;
- never source power back into the Pi;
- generate all major receiver rails locally from 5 V;
- design for Raspberry Pi `STANDBY`, where 5 V can remain present while 3.3 V is off;
- gate the main receiver power tree from Raspberry Pi active/3.3-V presence unless an explicit always-on option is selected;
- reserve the HAT+ identification EEPROM interface;
- preferred Pi/ECP5 runtime transport is SPI + interrupt/status;
- expose the same dedicated external PPS as the standalone board, with an optional copy to a Pi GPIO.

## Standalone USB-C variant

- USB-C is initially a 5 V sink;
- USB-PD is optional only if measured power requires it;
- use a controlled Type-C power path/load switch/eFuse;
- USB 2.0 data through the same connector is optional and independent of the receiver core;
- retain JTAG, dedicated PPS and a debug/control interface so the board is useful without a Raspberry Pi.

## Clock selection remains open

No exact TCXO OPN or nominal clock frequency is frozen yet.

The baseline is a **simple fixed TCXO**, with DCF77 frequency correction retained in the ECP5/sample scheduler. DCTCXO population remains an experimental option only if measured holdover performance justifies the extra control dependency.

Selection is based on:

1. synchronized timing target and holdover requirement;
2. exact orderable part availability at Digi-Key/Mouser;
3. temperature range and supply compatibility;
4. fixed-TCXO stability;
5. ECP5 PLL/sample-clock implementation;
6. measured/estimated EMI risk near 77.5 kHz;
7. lifecycle and sourcing depth.

See [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md).

## ADC block

Preferred Rev.0 chain:

```text
LTC6912 output
  -> AC coupling / 1.25 V rebias
  -> OPA2810 channel
  -> 51 ohm + 47 pF C0G isolation
  -> LTC1407A-1 CH0

optional diagnostic source
  -> OPA2810 channel
  -> 51 ohm + 47 pF C0G isolation
  -> LTC1407A-1 CH1
```

The ADC runs from a dedicated low-noise 3.3 V rail. The 2.5 V internal reference is locally bypassed and divided to create the 1.25 V ADC common-mode node.

## FPGA resource policy

The physical board may use an ECP5 LFE5U-45F for availability and debugging headroom, but the reference receiver build must stay within the historical XC3S1400AN resource envelope.

Machine-readable limits:

[`../../rtl/resource_budget.json`](../../rtl/resource_budget.json)
