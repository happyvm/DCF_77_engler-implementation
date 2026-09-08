# tscircuit hardware workspace

This directory is the future authoritative source for the DCF77 receiver schematic and PCB.

The project has intentionally **not** frozen `index.circuit.tsx` yet because the final ADC, input-stage replacement, regulator tree, ECP5 exact OPN, SPI flash, and SiTime exact ordering code must be selected before pin-level connectivity is committed.

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
  dist/
```

## Tooling policy

- tscircuit TSX is the editable hardware source of truth.
- Pin-accurate manufacturer data must be checked before part wrappers are committed.
- Critical analog/RF placement is explicit, not unconstrained autoplacement.
- AI/cloud autorouting is permitted after placement and netlist validation.
- KiCad export is mandatory for independent final review before fabrication.
- Generated KiCad/fabrication outputs are release artifacts, not a replacement for the tscircuit source.

See [`../../docs/14-hardware-cad-tscircuit.md`](../../docs/14-hardware-cad-tscircuit.md).

## Clock block already selected architecturally

The preferred clock source is a SiTime SiT5348 DCTCXO programmed for **24.180000 MHz**, feeding the ECP5 and controlled over I2C by the DCF77 carrier-discipline loop.

See [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md).
