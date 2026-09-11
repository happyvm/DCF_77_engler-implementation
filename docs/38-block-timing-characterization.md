# 38 — Block / subsystem timing characterisation infrastructure (BEA-37)

This document describes the **reproducible measurement infrastructure** used to
map the receiver's Fmax, resources, critical paths, latency and throughput from
the isolated block up to the full HAT top.  The goal is a *factual* map of where
the design loses frequency, resources or efficiency — not an early optimisation
pass.

Generated artefacts (versionable):

```
reports/timing/blocks.csv        reports/timing/blocks.md
reports/timing/subsystems.csv    reports/timing/subsystems.md
reports/timing/raw/<module>.json (full raw record per module)
```

## 1. How to run

```bash
make timing-block BLOCK=frequency_discipline
make timing-block BLOCK=engeler_goertzel_bank
make timing-block BLOCK=engeler_observables

make timing-subsystem SUBSYSTEM=goertzel_observables

make timing-all-blocks          # every isolated block
make timing-all-subsystems      # every subsystem
make timing-profile             # full campaign (blocks + subsystems + top)
make timing-reports             # regenerate CSV/MD from raw records
make timing-compare BEFORE=dir_before AFTER=dir_after
```

Multi-seed mode (placement-robustness check; the default is a single
deterministic seed for reproducibility):

```bash
make timing-all-blocks SEEDS=1,2,3,4
```

Every command **fails non-zero** if Yosys fails, nextpnr fails to finish, the
report cannot be parsed, or an expected artefact is missing.  There is no
silent success.

## 2. What is measured, and how

### 2.1 Same target, same flow

All benchmarks use the production ECP5 flow:

* device `LFE5U-45F-7BG256I`, speed grade `-7`;
* Yosys 0.52 `synth_ecp5` with the same script structure as
  `synth/release_reference.ys`;
* `nextpnr-ecp5 --45k --package CABGA256 --freq 125`;
* Fmax, worst slack, utilisation and critical paths are read from the
  **post-route** `nextpnr-ecp5 --report` JSON (never a pre-place estimate).

### 2.2 Pristine HEAD export

`make timing-*` first exports the **committed** `HEAD` RTL and synthesis tree
with `git archive HEAD rtl synth` into `build/timing/src/` and benchmarks that
pristine copy.  This makes results reproducible and, importantly on this
repository, **immune to other agents' in-flight edits**: the commit recorded in
the report is exactly the revision that was measured.  To characterise the live
working tree instead, commit first and re-run.

### 2.3 Isolated wrappers (registered in → DUT → registered out)

For every purely synchronous block the runner auto-generates a wrapper
(`build/timing/<module>/wrapper.sv`) following:

```
registered inputs  ->  DUT  ->  registered outputs
```

* every non-clock input is captured by a wrapper register driven by a
  free-running counter (a constant input would be folded away and prune the
  logic under test);
* every DUT output is registered inside the wrapper, then the registered
  outputs are XOR-folded into a compact signature and only `clk` + `sig_o`
  leave the wrapper.  The measured register-to-register path is therefore the
  DUT's internal combinational path — not a pad delay, an unregistered input, a
  top-level fanout artefact or an I/O path.  Folding to a signature also keeps
  every benchmark inside the CABGA256 IO budget (some composition blocks have
  > 250 output bits) and removes all unconstrained-IO noise;
* reset ports (`rst`/`rst_n`/`reset`/`reset_n`, matched by exact name so the
  functional `reset_cycle` input is *not* mistaken for a reset) are held
  inactive;
* the DUT's parameter block is re-emitted verbatim so its dimensions resolve,
  and the DUT is instantiated with its **production default parameters** unless
  the registry documents an override (see §2.6);
* the DUT is never modified, no widths are changed, no pipeline is added.

The only wrapper-added path is the shallow output signature fold
(`reg -> XOR tree -> sig_q`); it is a documented wrapper artefact and, on the
slow blocks where wide outputs exist, is far shorter than the DUT datapath.
A wrapper LPF constrains `clk` at 125 MHz.

For purely combinational blocks (e.g. `goertzel_complex_12`) there is no clock
port; the wrapper registers still bracket the DUT so the combinational depth is
measured between wrapper registers.

### 2.4 Physical interfaces

`adc_if`, `pga_spi_master`, `uart_tx`, `hat_spi_slave`, `lcd_i2c_driver` and
`i2c_master_byte` are wrapped the same way.  Their **external serial clocks /
data** (`adc_sdo`, `spi_sclk`, I2C `scl`/`sda`) are driven as ordinary data
inputs by the wrapper; the measurement is therefore the **internal clk-domain
path**, which is the actionable number for `clk_sys` timing.  Pad and external
interface timing are explicitly out of scope here.

### 2.5 Documented exceptions (no isolated benchmark)

| Module | Reason |
|---|---|
| `clock_reset_ecp5` | PLL + reset primitive; nextpnr times the EHXPLLL hard macro, not a clk-domain register path. Measured through `dcf77_hat_top`. |
| `dcf77_calendar_pkg` | SystemVerilog package, not a module. |
| `dcf77_hat_top` | Full HAT top, benchmarked in **direct mode** with the production LPF `synth/dcf77_hat_top.lpf` (clk_25m 25 MHz → PLL clk 125 MHz). |

### 2.6 Configuration overrides and `ifdef` ports

Two RTL idioms need explicit handling so a benchmark measures the real block
rather than an empty shell:

* `` `ifdef FORMAL `` observation ports (`pm_minute_sync`,
  `minute_candidate_search`) are added only for proofs.  With `FORMAL`
  undefined — as in every synthesis run — Yosys drops them; the wrapper's port
  parser applies the same preprocessor evaluation and drops them too, so the
  wrapper and the DUT agree.
* `receiver_lock_controller` has `QUALIFICATION_ENABLED = 0` by default, which
  forces `UNSYNC` and folds the whole FSM to an empty design.  Its benchmark
  therefore uses the documented override `QUALIFICATION_ENABLED = 1'b1`; the
  override is recorded in the report's `config` column (all other blocks are
  `production-defaults`).

## 3. Blocks and subsystems

### 3.1 Isolated blocks

`sample_scheduler`, `adc_if`, `pga_spi_master`, `goertzel_resonator`,
`goertzel_complex_12`, `engeler_goertzel_bank`, `engeler_observables`,
`am_bit_extractor`, `dcf77_prn_generator`, `pm_prn_correlator`,
`engeler_pm_correlator`, `pm_chip_integrator`, `engeler_pm_pipeline`,
`pm_phase_discriminator`, `second_phase_detector`, `pm_minute_sync`,
`second_evidence_aggregator`, `soft_history`, `ml_field_sequencer`,
`minute_candidate_search`, `hour_candidate_search`, `calendar_candidate_search`,
`ml_decoder_controller`, `receiver_lock_controller`, `frequency_discipline`,
`pps_generator`, `pps_uart`, `time_telemetry`, `uart_tx`, `hat_spi_slave`,
`lcd_i2c_driver`, `i2c_master_byte`, `engeler_detector`, `dcf77_receiver_core`.

### 3.2 Subsystems — the integration ladder

The RTL already exposes the natural integration ladder, so no synthetic
multi-instance compositions are needed:

```
engeler_goertzel_bank  <  engeler_observables  <  engeler_detector
                       <  dcf77_receiver_core  <  dcf77_hat_top
```

Registry mapping (`SUBSYSTEMS`):

| Subsystem | Composed module |
|---|---|
| `goertzel_observables` | `engeler_observables` (bank + 3× complex-12) |
| `receiver_dsp_core` | `engeler_detector` (+ AM + PM + sync) |
| `ml_decode_subsystem` | `ml_field_sequencer` (minute + hour + calendar) |
| `frequency_discipline_subsystem` | `frequency_discipline` |
| `full_receiver_core` | `dcf77_receiver_core` |
| `full_hat_top` | `dcf77_hat_top` (direct mode) |

Comparing a composition with the block it contains (e.g. `engeler_observables`
vs `engeler_goertzel_bank`) isolates the **integration/boundary loss** from the
isolated-block cost.

## 4. Block kind and timing-health classification

`kind` (in the registry) classifies each block:

* **single-cycle** — one operation per clock enable; a path must close every cycle.
* **multicycle** — the architecture explicitly spreads an operation over N clocks.
* **low-rate-control** — FSM/control updated far slower than `clk_sys`.
* **io-interface** — physical interface; the internal clk path is measured.
* **composition** — hierarchical composition of other blocks.
* **primitive** — vendor primitive (PLL); not benchmarked in isolation.

Indicative bands for blocks that must run at `clk_sys = 125 MHz`:

```
>= 200 MHz     excellent margin
175..200 MHz   very good
150..175 MHz   acceptable
125..150 MHz   weak margin
< 125 MHz      failing
```

This is an **analysis aid only**.  A `multicycle` or `low-rate-control` block is
annotated, not failed, when its isolated single path is slow, because the
architecture gives it more than one cycle.  The report shows both the band and
the kind.

## 5. Report schema

`blocks.csv` / `subsystems.csv` columns:

```
commit, date, module, kind, target_device, speed_grade, clock_target_mhz,
fmax_mhz, worst_slack_ns, lut4, ff, ebr18, mult18x18d, pll,
latency_cycles, throughput, critical_path_summary, seed, tool_versions,
multiplications, additions, comparators, total_cells, wire_bits, timing_met
```

* `worst_slack_ns = 1000/clock_target − 1000/fmax` (negative ⇒ misses target).
* `latency_cycles` / `throughput` are explicit strings; `N/A` is used when a
  value genuinely does not apply (never an ambiguous omission).
* The **FPGA-specific** metrics (`lut4`, `ebr18`, `mult18x18d`) are separated
  from the **architectural/generic** metrics (`multiplications`, `additions`,
  `comparators`, `total_cells`, `wire_bits`, plus latency/throughput) so a
  future ASIC comparison can read the latter without the technology counts.
  These generic counts are an *approximate* operator census from
  `stat` after `proc; opt` — **not** an ASIC area estimate.

## 6. Latency and throughput

Latency / throughput are recorded per block in the registry and reproduced in
`blocks.csv`.  They exist so the report can show *why* a slow isolated path is
or is not a problem, e.g.:

```
engeler_observables    latency: 6 clk to observable_valid (pipeline)
                       throughput: 1 sample per clk (gated by sample_ce)
frequency_discipline   latency: 1 clk observation, once per second
                       throughput: 1 correction per measurement_ce interval
```

Blocks updated only once per second (discipline, minute sync, ML search) have
orders of magnitude of spare cycles, which is exactly the head-room that makes
multi-cycle sharing viable; the architecture should not be judged by a single
combinational path that is deliberately not exercised every cycle.

## 7. Comparing two commits

```bash
# campaign at commit A -> reports/timing/raw ; copy it
cp -r reports/timing/raw /tmp/before
git checkout <commit B> && make timing-all-blocks
cp -r reports/timing/raw /tmp/after
python3 tools/timing/compare.py --before /tmp/before --after /tmp/after
```

The comparison prints, per common block, Fmax, slack, LUT/FF/EBR/MULT,
generic multiplication count and latency, with the Fmax/LUT/MULT deltas, so the
resource/Fmax/latency/throughput trade-off is visible.

## 8. Tests

`tests/test_timing_parse.py` exercises the parsers against committed fixtures
(`tests/fixtures/nextpnr_report_fixture.json`,
`tests/fixtures/nextpnr_log_fixture.txt`) plus the port parser, wrapper
generator and health classification.  A change of nextpnr report/log format
therefore fails the tests instead of silently corrupting `blocks.csv`.  These
run as part of `make test-tools`.

## 9. Result snapshot

See `reports/timing/blocks.md` and `reports/timing/subsystems.md` for the
current measured campaign, and the BEA-37 final report
(`docs/39-timing-characterization-results.md`) for the analysis, top-10
slowest blocks, critical paths, integration losses and ranked recommendations.
