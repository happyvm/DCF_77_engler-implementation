# Hardware CAD workflow: tscircuit -> KiCad

## Decision

The rebuild schematic and PCB are authored in **tscircuit**.

The tscircuit TypeScript/TSX source is the project-controlled hardware source of truth. KiCad files are generated/exported artifacts used for review, manufacturing checks, hand finishing where necessary, and exchange with conventional EDA workflows.

```text
hardware/tscircuit source
        |
        +--> schematic/PCB previews
        +--> Circuit JSON
        +--> placement checks
        +--> local/cloud autorouting
        +--> fabrication outputs
        +--> KiCad export
                    |
                    v
             KiCad inspection
             DRC / final review
```

This policy is intended to make the board reproducible, reviewable in code, and suitable for AI-assisted placement/routing without making an opaque online layout the only editable design record.

## Why tscircuit fits this project

tscircuit currently provides:

- schematics and PCB layout from TypeScript/React-style source;
- explicit component placement controls;
- automatic and cloud autorouting;
- customizable autorouter APIs;
- fabrication-file generation;
- Circuit JSON as an intermediate representation;
- conversion/export to KiCad schematic and PCB formats;
- AI-oriented board generation workflows.

The official tscircuit guidance recommends validating connectivity and placement before enabling routing, then iterating with placement checks and PCB snapshots.

## Repository structure

The intended hardware tree is:

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
        ... reusable symbols/footprints/part wrappers ...
      board/
        placement.ts
        constraints.ts
    dist/
      ... generated files; not authoritative ...
```

The board should be decomposed into electrical/physical blocks rather than defining every component in one file.

## Source-of-truth rule

Changes that affect electrical connectivity, component choice, footprint, or intended placement must be represented back in tscircuit source.

Do not allow a hand-edited KiCad export to silently become the only copy of an important design change.

If KiCad is used to repair or optimize something that tscircuit cannot yet represent cleanly:

1. record the change;
2. port the intent back to tscircuit where possible;
3. regenerate the export;
4. compare the regenerated and hand-reviewed board.

For a release, archive both the tscircuit source revision and the exact reviewed KiCad/fabrication output.

## Recommended design sequence

### 1. Connectivity first

Create the full schematic/netlist before optimizing PCB routing.

Each block must expose explicit named interfaces so component substitutions remain manageable, for example:

```text
ANT_P / ANT_N
AFE_OUT
ADC_IN_P / ADC_IN_N
ADC_CNV / ADC_SCK / ADC_SDO
TCXO_CLK
TCXO_SCL / TCXO_SDA
PGA_CS / PGA_SCK / PGA_MOSI
JTAG_*
USB/debug
```

### 2. Place critical components manually

For this receiver, AI/autoplacement must not decide all placement freely.

The following physical relationships are RF-critical and should be constrained explicitly:

- ferrite antenna far from FPGA, USB and switch-mode regulators;
- input buffer immediately beside the antenna interface;
- band-pass and PGA kept in the quiet analog region;
- ADC at the analog/digital boundary;
- TCXO kept away from the ferrite/input node and noisy switch nodes;
- ECP5, configuration flash and digital regulators grouped together;
- decoupling directly at every supply pin/group;
- test points accessible without long high-impedance stubs.

### 3. Check placement before routing

Use the current tscircuit placement/build checks and inspect generated PCB images before routing.

The acceptance criteria are not merely "no overlap". Review:

- analog/digital partitioning;
- antenna clearance;
- connector accessibility;
- decoupling distances;
- current-return paths;
- clock-trace length/exposure;
- switch-node distance from the receiver front end;
- BGA escape feasibility;
- test-point accessibility.

### 4. Route in stages

Preferred order:

1. power and ground strategy;
2. antenna/input analog path;
3. filter/PGA/ADC analog path;
4. TCXO and clock path;
5. ADC digital interface;
6. ECP5 configuration/JTAG;
7. remaining slow control buses;
8. USB/display/debug last.

Use local or cloud autorouting only after the placement is credible.

For complex routing tscircuit supports cloud autorouters and an autorouting API; the routing output must still be reviewed for this unusually noise-sensitive receiver.

## AI-assisted placement/routing policy

Online/AI layout is welcome as an optimization assistant, not as an authority on RF behaviour.

The AI may propose:

- component packing;
- BGA fan-out;
- trace/via minimization;
- alternative routing solutions;
- decoupling placement improvements;
- mechanical-space optimization.

It must not override hard constraints such as:

- the ferrite keepout;
- quiet analog region;
- no fast clock under/near antenna input;
- switcher keepout;
- sensitive return-path rules;
- explicit board-edge connector orientation;
- test access requirements.

Every AI-generated board revision must pass deterministic checks and human visual review.

## KiCad export

tscircuit's current toolchain includes conversion from Circuit JSON to KiCad schematic (`.kicad_sch`), PCB (`.kicad_pcb`) and project formats. The CLI also supports export workflows such as `kicad_pcb` / `kicad_zip` depending on the installed version.

Typical release workflow:

```bash
# evaluate/build circuit
npx tsci build index.circuit.tsx

# inspect locally
npx tsci dev index.circuit.tsx

# generate PCB/schematic snapshots as supported by the installed CLI
npx tsci snapshot index.circuit.tsx

# export KiCad bundle (exact switches are pinned with the project CLI version)
npx tsci export index.circuit.tsx -f kicad_zip -o dist/dcf77-receiver.kicad.zip
```

The project must pin the tested tscircuit/CLI versions; do not rely indefinitely on an unversioned global CLI.

## Mandatory KiCad post-export validation

The KiCad export must be opened and checked before manufacturing.

At minimum:

- run KiCad ERC/DRC as applicable;
- verify every BGA/IC pad number against the source pinout;
- verify board outline and any cutouts;
- verify silkscreen text size/thickness;
- verify copper zones and ground planes;
- inspect all via drill/annular-ring settings;
- verify net classes/clearances;
- compare critical component coordinates against tscircuit intent;
- regenerate Gerbers from the reviewed project and inspect them independently.

This is especially important because tscircuit/KiCad integration is under active development. Recent 2026 issue reports have included exporter problems involving silkscreen font scaling and interior cutouts. These are reasons for post-export checking, not reasons to abandon the coded workflow.

## Version/reproducibility policy

Before the first PCB release, commit:

- `package.json` lockfile;
- exact tscircuit CLI/core versions;
- any custom footprint modules;
- exact autorouter configuration/provider;
- board screenshots;
- exported Circuit JSON;
- reviewed KiCad bundle;
- manufacturing Gerbers/BOM/PnP outputs;
- a release checklist recording DRC/ERC results.

## Manufacturing source hierarchy

During development:

```text
tscircuit source = authoritative design intent
```

For a fabricated revision:

```text
tscircuit source + reviewed release export + fabrication files
```

form the immutable release record.

The goal is to be able to regenerate a functionally identical board even if a particular online AI/autorouter service later changes or disappears.

## References

- tscircuit documentation: https://docs.tscircuit.com/
- tscircuit repository: https://github.com/tscircuit/tscircuit
- tscircuit CLI: https://github.com/tscircuit/cli
- autorouting API documentation: https://github.com/tscircuit/docs/blob/main/docs/web-apis/autorouting-api.mdx
- KiCad converter: https://github.com/tscircuit/circuit-json-to-kicad
