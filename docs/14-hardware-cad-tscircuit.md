# Hardware CAD workflow: tscircuit -> KiCad -> Quilter -> KiCad

## Decision

The rebuild schematic and PCB are authored in **tscircuit**.

Rev.0 now has one physical board only: the Raspberry Pi Standard HAT+.

The tscircuit TypeScript/TSX source is the project-controlled hardware source of truth. KiCad is the interchange/review format used for Quilter placement/routing and final engineering review.

```text
hardware/tscircuit source
        |
        +--> schematic / Circuit JSON / board constraints
        v
   KiCad export
        |
        +--> HAT+ board outline
        +--> stackup / DRC rules
        +--> placement regions
        +--> keepouts
        +--> mechanically/RF-critical locked parts
        v
      Quilter
 placement + routing
        v
 native KiCad result
        |
        +--> engineering review
        +--> DRC / ERC
        +--> RF/EMI inspection
        v
 Gerbers / BOM / PnP / release archive
```

Quilter is not the source of electrical intent and a generated layout is never released without independent review.

## Source-of-truth rule

The authoritative design intent includes:

- connectivity;
- component/footprint selection;
- Raspberry Pi HAT+ mechanics;
- RF/mechanical keepouts;
- mandatory placement relationships;
- net classes and critical-net intent;
- power-domain intent.

Changes to connectivity, components, footprints or required placement must be represented back in tscircuit.

For each fabrication revision archive both:

1. exact tscircuit source revision;
2. exact reviewed post-Quilter KiCad project used for fabrication.

## Repository structure

Target structure:

```text
hardware/tscircuit/
  pin-plan.json
  power-plan.json
  package.json
  tsconfig.json
  src/
    index.tsx
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      pps.tsx
      display.tsx
      receiver_power.tsx
    board/
      raspberry_pi_hatplus.tsx
      hatplus_constraints.ts
      quilter.ts
    host/
      rpi_spi.tsx
    power/
      hat_5v_input.tsx
    parts/
  dist/
    circuit-json/
    kicad-pre-quilter/
    kicad-post-quilter/
    fabrication/
```

There is no standalone/USB-C board source tree in Rev.0.

## Locked before Quilter

Quilter must not freely decide:

- Raspberry Pi 40-pin connector position;
- HAT+ mounting holes/outline;
- integrated ferrite position/orientation;
- antenna tuning parts;
- OPA810 high-impedance input cluster;
- LCD mechanical position;
- external PPS connector/test interface;
- any enclosure/shield-critical objects.

## Constrained regions

Quilter may optimize within predefined regions for:

- LTC1562 band-pass;
- LTC6912 PGA;
- ADC/driver/LT3042;
- ECP5/configuration flash;
- TCXO/TPS7A2033;
- 1.1 V digital power;
- Raspberry Pi host/debug interface.

Reference floorplan intent:

```text
+------------------------------------------------------------+
| quiet ferrite/AFE | filter/PGA | ADC | ECP5 / Pi host     |
|                   |            |     | TCXO / flash / PPS  |
|                   |            |     | core power          |
+------------------------------------------------------------+
```

The ferrite is placed at the HAT edge farthest from Raspberry Pi digital/power activity.

## Hard layout constraints

### Antenna/input

- no fast Pi/FPGA trace under ferrite/input region;
- no switching-regulator node nearby;
- no ECP5 clock trace nearby;
- minimize `ANT_IN` copper length;
- no unnecessary test stubs on the high-impedance node.

### Clock

- SiT5356 physically separated from ferrite/first analog stage;
- short direct route to ECP5 `C9`;
- no long clock test stub;
- clock return current stays in digital region.

### ADC boundary

- ADC at analog/digital boundary;
- LT3042, OPA2835 and ADC decoupling compact;
- ADC digital signals leave toward ECP5;
- reference/common-mode network protected from digital return currents.

### Power

- the sole local switching buck (`1V1_CORE`) is in the digital region;
- no SW node/inductor near AFE or TCXO;
- `PI_3V3` distribution stays in HAT/digital region;
- `PI_5V` reaches the power tree without crossing the AFE first;
- analog rails are filtered/post-regulated as defined in `power-plan.json`.

## Routing priorities

1. antenna/input analog path;
2. filter/PGA/ADC analog path;
3. ADC reference/common-mode/power;
4. TCXO -> ECP5 clock;
5. FPGA power/configuration/JTAG;
6. ADC digital interface;
7. PGA/LCD low-rate control;
8. Raspberry Pi host SPI/debug last.

The goal is lowest DCF77 sensitivity/timing risk, not minimum total copper.

## Quilter iteration loop

```text
1. build/export tscircuit -> KiCad
2. inspect pre-Quilter HAT project
3. lock critical placements and verify constraints
4. submit KiCad design to Quilter
5. inspect returned placement/routing candidates
6. review RF/EMI-sensitive regions manually
7. fix source constraints if needed
8. repeat until acceptable
9. freeze reviewed KiCad revision
10. run final ERC/DRC/Gerber review
```

## Mandatory post-Quilter review

A DRC-clean board can still be a poor DCF77 receiver. Review:

- ferrite clearance/quiet-zone integrity;
- OPA810/tuning parasitics;
- analog return paths;
- LTC1562 resistor grouping;
- ADC reference/driver geometry;
- ECP5 BGA escape and plane continuity;
- decoupling;
- oscillator coupling paths;
- 1.1 V buck hot loop;
- Raspberry Pi host/supply coupling into RF region;
- PPS route;
- test-point stubs;
- assembly/thermal feasibility.

## KiCad export

Conceptual pinned-version flow:

```bash
npx tsci build src/index.tsx
npx tsci dev src/index.tsx
npx tsci snapshot src/index.tsx
npx tsci export src/index.tsx -f kicad_zip -o dist/kicad-pre-quilter/dcf77-hat.zip
```

The exact command is frozen with the pinned tscircuit toolchain before release.

## BGA export safety

The ECP5 BG256 pad identity is safety-critical. The tscircuit part wrapper and KiCad export must be automatically checked against:

- current Lattice `FPGA-SC-02034` pinout;
- `hardware/tscircuit/pin-plan.json`;
- audited BGA256 footprint pad identities.

Do not release fabrication output if ball names were renumbered or reordered by an exporter.

## Version/reproducibility policy

Archive for every Quilter iteration:

- git commit SHA;
- pinned tscircuit versions;
- pre-Quilter KiCad checksum;
- constraints used;
- selected returned candidate;
- post-Quilter KiCad checksum;
- engineering review notes.

For fabrication additionally archive:

- final ERC/DRC results;
- Gerbers/drill files;
- BOM/PnP;
- stackup/fabrication notes;
- release checklist.

## References

- tscircuit documentation/repository.
- tscircuit Circuit JSON / KiCad converter.
- Quilter product/workflow documentation.
- Raspberry Pi HAT+ Specification.
- Lattice ECP5 BG256 pinout/package documentation.
