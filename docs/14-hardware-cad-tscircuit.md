# Hardware CAD workflow: tscircuit -> KiCad -> Quilter -> KiCad

## Decision

The rebuild schematic and PCB are authored in **tscircuit**.

The tscircuit TypeScript/TSX source is the project-controlled hardware source of truth. KiCad is the interchange/review format used to hand the board to **Quilter** for AI-assisted placement and routing, then to inspect and finish the returned native KiCad project before fabrication.

```text
hardware/tscircuit source
        |
        +--> schematic / Circuit JSON / board constraints
        |
        v
   KiCad export
        |
        +--> board outline
        +--> stackup / DRC rules
        +--> placement regions
        +--> keepouts
        +--> mechanically/RF-critical locked parts
        |
        v
      Quilter
 placement + routing
        |
        v
 native KiCad result
        |
        +--> engineering review
        +--> DRC / ERC
        +--> RF/EMI inspection
        +--> manual corrections if required
        |
        v
 Gerbers / BOM / PnP / release archive
```

This policy keeps the design reproducible in code while using Quilter specifically as the placement/routing engine. Quilter is not the source of electrical intent and a generated layout is never released without independent review.

## Why tscircuit fits this project

tscircuit provides a code-defined schematic/PCB source, explicit component placement, Circuit JSON and export paths to KiCad. That makes it suitable for a design where component substitutions, lifecycle decisions and physical RF constraints need to remain version-controlled.

The authoritative design intent includes:

- electrical connectivity;
- component/footprint selection;
- board outline;
- RF and mechanical keepouts;
- mandatory placement relationships;
- net classes and critical-net intent;
- power-domain intent.

## Why Quilter is the placement/routing engine

Quilter currently accepts complete designs from supported ECAD tools including KiCad, performs placement and routing, and returns native design files for review and editing.

For this project that means Quilter gets a **prepared KiCad project**, not an unconstrained raw netlist.

Before submission we provide:

- complete schematic/netlist;
- final board outline for the iteration;
- mounting holes and mechanically fixed connectors;
- stackup;
- KiCad DRC rules/net classes;
- differential/impedance rules where applicable;
- placement regions/rooms where useful;
- explicit keepouts;
- locked RF/mechanical components.

Quilter's own workflow recommends setting this intent before generation and iterating on returned candidates rather than treating the first result as final.

## Repository structure

```text
hardware/
  tscircuit/
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

`dist/` contains generated/review artifacts and is never the only copy of design intent.

## Source-of-truth rule

Changes that affect electrical connectivity, component choice, footprint or required physical placement must be represented back in tscircuit source.

A Quilter/KiCad result can contain routing details that are not practical to encode directly in tscircuit. For each fabricated revision we therefore archive both:

1. the exact tscircuit source revision that generated the candidate;
2. the exact reviewed post-Quilter KiCad project used for fabrication.

If engineering review changes connectivity, footprints or a mandatory placement rule in KiCad, that intent must be ported back to tscircuit before the next design iteration.

## Placement ownership

### Locked before Quilter

Quilter must **not** freely decide the following positions:

- ferrite antenna connector / antenna mechanical interface;
- high-impedance first input device;
- critical tuning components immediately around the antenna input;
- board-edge connectors whose position is mechanical;
- mounting holes;
- any shield-can outline or enclosure-critical object.

The first analog stage should be treated as a manually defined RF island rather than a generic collection of components.

### Constrained regions

Quilter may optimize placement inside predefined regions for:

- analog band-pass;
- PGA;
- ADC/driver;
- ECP5/configuration flash;
- clock source;
- digital power;
- USB/debug.

The desired board floorplan is approximately:

```text
+-----------------------------------------------------------+
| ANT / quiet RF | analog filter | ADC | digital / ECP5    |
|                | PGA           |     | clock / flash      |
|                |               |     | USB/debug/power    |
+-----------------------------------------------------------+
```

with physical distance and return-path control between the ferrite/input region and high-activity digital circuitry.

## Hard layout constraints for Quilter

The constraints below are engineering requirements, not optimization suggestions.

### Antenna/input region

- no fast digital trace under the ferrite/input region;
- no switching-regulator node nearby;
- no USB routing nearby;
- no ECP5 clock trace nearby;
- minimize the high-impedance antenna-to-input-device connection;
- preserve a clean reference/return strategy appropriate to the analog topology;
- avoid unnecessary test-point stubs on the high-impedance node.

### Clock source

- keep oscillator/TCXO physically separated from ferrite and first analog stage;
- short direct clock route to ECP5 clock input;
- no large clock test stub;
- keep clock return current confined to the digital region;
- evaluate harmonic relationships to 77.5 kHz before clock-source freeze.

### ADC boundary

- ADC sits at the analog/digital boundary;
- analog driver and ADC decoupling remain compact;
- digital outputs leave toward ECP5, not across the analog section;
- conversion/sample clock is routed as a critical digital net;
- reference/common-mode network is protected from digital return currents.

### Power

- switching converters belong in the noisiest/farthest digital region;
- sensitive analog rails use appropriate filtering/post-regulation;
- decoupling stays close to the corresponding pins;
- plane splits or stitching strategy must follow actual return-current analysis, not arbitrary analog/digital ground labels.

## Routing priorities

Quilter handles the routing candidate, but the design intent should express roughly this priority:

1. antenna/input analog path;
2. analog filter/PGA/ADC path;
3. ADC reference/common-mode/power;
4. clock source and FPGA clock input;
5. FPGA power/configuration/JTAG;
6. ADC digital interface;
7. low-rate controls such as PGA/I2C;
8. USB/display/debug last.

The goal is not necessarily the shortest total copper. The goal is lowest risk to DCF77 sensitivity and timing integrity.

## Quilter iteration loop

Expected workflow per board revision:

```text
1. build/export tscircuit -> KiCad
2. inspect pre-Quilter KiCad project
3. lock critical placements and verify constraints
4. upload native KiCad design to Quilter
5. generate multiple placement/routing candidates where useful
6. inspect physics/DRC results
7. download selected native KiCad candidate
8. review RF/EMI-sensitive areas manually
9. correct constraints/source intent if needed
10. resubmit for another Quilter iteration
11. freeze reviewed KiCad revision
12. run final DRC/ERC and Gerber inspection
```

Quilter states that real projects often go through several engineer-review/resubmission cycles. That matches our intended process.

## What must be reviewed after Quilter

A DRC-clean board can still be a poor DCF77 receiver.

Mandatory human review includes:

- antenna clearance and quiet-zone integrity;
- first-stage trace lengths and parasitics;
- analog return paths;
- filter component physical grouping;
- ADC reference/driver geometry;
- FPGA BGA escape and plane continuity;
- decoupling effectiveness;
- oscillator/clock coupling paths;
- switching-regulator hot loops;
- USB/debug coupling toward the RF region;
- ground-return crossings under sensitive traces;
- via fences/shield provisions where useful;
- test-point stubs;
- thermal and assembly feasibility.

Then run KiCad DRC/ERC and inspect generated Gerbers independently.

## KiCad export from tscircuit

tscircuit's conversion toolchain can produce KiCad schematic/PCB project artifacts from the code-defined design.

The exact CLI command is pinned with the project version before Rev.0 release. The conceptual flow is:

```bash
npx tsci build index.circuit.tsx
npx tsci dev index.circuit.tsx
npx tsci snapshot index.circuit.tsx
npx tsci export index.circuit.tsx -f kicad_zip -o dist/kicad-pre-quilter/dcf77-receiver.zip
```

Because the converter is actively developed, the pre-Quilter export is checked before upload and the returned post-Quilter project is checked again before fabrication.

## Version/reproducibility policy

For every submitted Quilter iteration archive:

- git commit SHA of tscircuit source;
- pinned tscircuit dependency/CLI versions;
- pre-Quilter KiCad archive checksum;
- Quilter submission date/job identifier if available;
- constraints used for the run;
- selected returned candidate;
- post-Quilter KiCad archive checksum;
- screenshots/notes from engineering review.

For every fabrication release additionally archive:

- final KiCad DRC/ERC result;
- Gerbers;
- drill files;
- BOM;
- pick-and-place;
- stackup/fabrication notes;
- reviewed PDF/plots if generated;
- release checklist.

## Manufacturing source hierarchy

During schematic/PCB development:

```text
tscircuit = authoritative electrical and physical design intent
```

During layout optimization:

```text
KiCad export -> Quilter -> reviewed KiCad
```

For a fabricated board revision:

```text
tscircuit source revision
+ reviewed post-Quilter KiCad project
+ exact manufacturing package
= immutable release record
```

## References

- tscircuit documentation: https://docs.tscircuit.com/
- tscircuit repository: https://github.com/tscircuit/tscircuit
- tscircuit KiCad converter: https://github.com/tscircuit/circuit-json-to-kicad
- Quilter product/workflow: https://www.quilter.ai/product
