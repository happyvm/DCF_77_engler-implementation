# tscircuit hardware workspace

This directory is the future authoritative source for the DCF77 receiver schematic and PCB design intent.

The project will produce **two PCB variants from one shared receiver core**:

1. Raspberry Pi Standard HAT+ — powered from the Raspberry Pi 5 V GPIO-header rail;
2. standalone board — powered from USB-C as a 5 V sink.

The analog front end, ADC, clock, ECP5, DSP boundary and downstream receiver power tree should remain shared wherever possible.

The project has intentionally **not** frozen `index.circuit.tsx` yet because several pin-level choices are still open: final ADC/driver, sustainable input stage, regulator tree, exact ECP5 OPN, SPI flash and final stocked DCTCXO OPN/frequency.

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
  -> AFE
  -> ADC
  -> clock
  -> ECP5
```

Only the 5 V input shell differs:

```text
HAT+:
Raspberry Pi 5V -> protected/gated input -> 5V_SYS

standalone:
USB-C VBUS -> Type-C sink/power path -> 5V_SYS
```

The HAT+ variant should use Raspberry Pi 3.3 V only for HAT identification / power-state sensing as required, not as the main FPGA/analog supply.

## RF-critical placement policy

The following are not freely placed by Quilter:

- antenna mechanical interface;
- first high-impedance input device;
- critical antenna tuning components;
- mounting holes;
- mechanically fixed board-edge connectors.

Analog, ADC, clock, FPGA, USB/debug and power blocks receive placement regions/keepouts so Quilter optimizes within the intended RF floorplan rather than inventing the floorplan itself.

The HAT+ and standalone boards have different interference environments, so their placement constraints are variant-specific even though the receiver topology is shared.

## Raspberry Pi HAT+ variant

- follow the current HAT+ specification, not the deprecated original HAT standard;
- powered from the Raspberry Pi 5 V header pins;
- never source power back into the Pi;
- generate all major receiver rails locally from 5 V;
- design for Raspberry Pi `STANDBY`, where 5 V can remain present while 3.3 V is off;
- preferred implementation gates the main receiver power tree from Raspberry Pi active/3.3-V presence so the FPGA cannot back-power unpowered GPIO;
- reserve the HAT+ identification EEPROM interface;
- preferred Pi/ECP5 runtime transport is SPI + interrupt/status rather than a large parallel GPIO bus.

## Standalone USB-C variant

- USB-C is initially a 5 V sink;
- USB-PD is optional and should only be added if the measured power budget requires it;
- use a controlled Type-C power path/load switch/eFuse rather than attaching large board capacitance directly to VBUS;
- USB 2.0 data through the same connector is optional and independent of the receiver core;
- retain JTAG, PPS and a debug/control interface so the board is useful without a Raspberry Pi.

## Clock selection remains open

No SiTime OPN or nominal clock frequency is frozen yet.

Selection is based on:

1. final synchronized timing target and holdover requirement;
2. exact orderable part availability at major distributors such as Digi-Key/Mouser;
3. temperature range and supply compatibility;
4. digital frequency-control capability;
5. ECP5 PLL/sample-clock implementation;
6. measured/estimated EMI risk near 77.5 kHz;
7. lifecycle and sourcing depth.

The current baseline is a stocked **SiTime DCTCXO class around ±100 ppb**, with ±50 ppb reserved for cases where the final error/holdover budget justifies it.

See [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md).

## FPGA resource policy

The physical board may use an ECP5 LFE5U-45F for availability and debugging headroom, but the reference receiver build must stay within the historical XC3S1400AN resource envelope.

Machine-readable limits are in:

[`../../rtl/resource_budget.json`](../../rtl/resource_budget.json)
