# tscircuit hardware workspace

This directory is the future authoritative source for the DCF77 receiver schematic and PCB design intent.

The project has intentionally **not** frozen `index.circuit.tsx` yet because several pin-level choices are still open: final ADC/driver, sustainable input stage, regulator tree, exact ECP5 OPN, SPI flash and final stocked DCTCXO OPN/frequency.

## Planned structure

```text
hardware/tscircuit/
  index.circuit.tsx
  package.json
  tsconfig.json
  src/
    blocks/
      antenna.tsx
      input_stage.tsx
      bandpass.tsx
      pga.tsx
      adc.tsx
      clock.tsx
      ecp5.tsx
      power.tsx
      debug.tsx
    parts/
    board/
      placement.ts
      constraints.ts
      quilter.ts
  dist/
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
- The tscircuit design is exported to KiCad, prepared with outline/stackup/rules/locked critical placements, and submitted to Quilter.
- Quilter returns native KiCad candidates for engineering review.
- A Quilter result is not fabrication-ready merely because it is routed or DRC-clean.
- Final KiCad inspection/DRC and Gerber review are mandatory before fabrication.
- Electrical/footprint/mandatory-placement changes discovered during KiCad/Quilter review must be represented back in tscircuit for the next iteration.

See [`../../docs/14-hardware-cad-tscircuit.md`](../../docs/14-hardware-cad-tscircuit.md).

## RF-critical placement policy

The following are not freely placed by Quilter:

- antenna mechanical interface;
- first high-impedance input device;
- critical antenna tuning components;
- mounting holes;
- mechanically fixed board-edge connectors.

Analog, ADC, clock, FPGA, USB/debug and power blocks receive placement regions/keepouts so Quilter optimizes within the intended RF floorplan rather than inventing the floorplan itself.

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
