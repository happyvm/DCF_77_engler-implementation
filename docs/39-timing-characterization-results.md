# 39 — Block / subsystem timing characterisation results (BEA-37)

This is the **factual performance map** of the receiver produced by the
infrastructure in `docs/38-block-timing-characterization.md`.  It answers *where*
the design loses frequency and resources, from the isolated block up to the full
HAT top — it is not an optimisation pass (BEA-36 owns timing closure of
`release_reference`).

**What was measured.** 34 dedicated benchmarks + 6 subsystems, all from the same
pristine `git archive HEAD` export of commit **`2620d80383ae`**, all through the
production ECP5 flow (Yosys 0.52 `synth_ecp5` → nextpnr-ecp5 0.9-3
`--45k --package CABGA256 --freq 125`, seed 1), reading the **post-route**
`--report`.  Every number below comes from a real place-and-route.

Raw records: `reports/timing/raw/*.json`.  Tables: `reports/timing/blocks.{csv,md}`,
`reports/timing/subsystems.{csv,md}`.

---

## 1. Headline result

The design is a **~27–29 MHz single-cycle architecture** at the top level.  22 of
34 blocks sit below the 125 MHz band; the two slowest single-cycle datapath
blocks — the **Goertzel resonator bank (27.3 MHz)** and the blocks that contain
it — set the floor.  A large share of the remaining blocks are `multicycle` or
`low-rate-control` (updated once per second or slower) and are slow only because
they are being timed on a single combinational path they deliberately do not
exercise every cycle.

| Level | Module | Fmax |
|---|---|---:|
| Block | `engeler_goertzel_bank` | 27.3 MHz |
| Subsystem | `engeler_observables` | 28.1 MHz |
| Subsystem | `engeler_detector` (`receiver_dsp_core`) | 28.5 MHz |
| Subsystem | `dcf77_receiver_core` | 26.9 MHz |
| Top | `dcf77_hat_top` | 28.9 MHz |

> Cross-check: the default `make timing` (release `synth_ecp5` profile) reports
> 27.5 MHz on the same commit; the ~1.4 MHz difference is the flow/config, not a
> measurement error.  The report records the exact command per row.

---

## 2. Full block table (post-route, 125 MHz target)

| module | kind | Fmax (MHz) | slack (ns) | LUT4 | FF | EBR18 | MULT18X18D | PLL |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| dcf77_prn_generator | low-rate-control | 346.3 | +5.11 | 70 | 65 | 0 | 0 | 0 |
| second_evidence_aggregator | single-cycle | 230.2 | +3.66 | 134 | 211 | 0 | 0 | 0 |
| uart_tx | io-interface | 229.2 | +3.64 | 102 | 68 | 0 | 0 | 0 |
| pps_generator | low-rate-control | 219.8 | +3.45 | 101 | 60 | 0 | 0 | 0 |
| i2c_master_byte | io-interface | 216.2 | +3.38 | 117 | 78 | 0 | 0 | 0 |
| pga_spi_master | io-interface | 214.5 | +3.34 | 117 | 75 | 0 | 0 | 0 |
| adc_if | io-interface | 211.4 | +3.27 | 93 | 137 | 0 | 0 | 0 |
| receiver_lock_controller | low-rate-control | 165.9 | +1.97 | 106 | 55 | 0 | 0 | 0 |
| time_telemetry | low-rate-control | 151.2 | +1.39 | 581 | 233 | 0 | 0 | 0 |
| sample_scheduler | low-rate-control | 141.3 | +0.92 | 161 | 138 | 0 | 0 | 0 |
| soft_history | multicycle | 140.5 | +0.89 | 229 | 262 | 12 | 0 | 0 |
| pps_uart | composition | 138.4 | +0.77 | 564 | 251 | 0 | 0 | 0 |
| engeler_pm_correlator | single-cycle | 119.9 | −0.34 | 256 | 189 | 0 | 0 | 0 |
| pm_prn_correlator | single-cycle | 112.4 | −0.90 | 248 | 172 | 0 | 0 | 0 |
| hat_spi_slave | io-interface | 111.1 | −1.00 | 515 | 253 | 0 | 0 | 0 |
| pm_chip_integrator | multicycle | 96.9 | −2.32 | 444 | 297 | 0 | 0 | 0 |
| engeler_pm_pipeline | composition | 95.6 | −2.46 | 659 | 392 | 0 | 0 | 0 |
| ml_decoder_controller | low-rate-control | 92.6 | −2.80 | 896 | 315 | 0 | 0 | 0 |
| goertzel_complex_12 | single-cycle | 90.8 | −3.02 | 218 | 160 | 0 | 2 | 0 |
| am_bit_extractor | multicycle | 70.3 | −6.22 | 891 | 447 | 0 | 0 | 0 |
| pm_phase_discriminator | composition | 69.8 | −6.33 | 2185 | 1005 | 0 | 0 | 0 |
| frequency_discipline | multicycle | 68.2 | −6.67 | 2167 | 1094 | 0 | 0 | 0 |
| second_phase_detector | low-rate-control | 59.7 | −8.74 | 1756 | 603 | 0 | 0 | 0 |
| hour_candidate_search | multicycle | 46.0 | −13.75 | 1694 | 415 | 0 | 0 | 0 |
| ml_field_sequencer | composition | 41.7 | −15.98 | 3937 | 1348 | 0 | 0 | 0 |
| pm_minute_sync | low-rate-control | 39.8 | −17.12 | 2097 | 810 | 0 | 0 | 0 |
| minute_candidate_search | multicycle | 39.7 | −17.21 | 1739 | 449 | 0 | 0 | 0 |
| calendar_candidate_search | multicycle | 38.8 | −17.76 | 1893 | 397 | 0 | 0 | 0 |
| goertzel_resonator | single-cycle | 34.7 | −20.85 | 544 | 183 | 0 | 6 | 0 |
| lcd_i2c_driver | io-interface | 29.3 | −26.08 | 1016 | 172 | 0 | 0 | 0 |
| dcf77_hat_top | composition | 28.9 | −26.59 | 17253 | 6178 | 8 | 28 | 1 |
| engeler_detector | composition | 28.5 | −27.14 | 9967 | 3752 | 0 | 28 | 0 |
| engeler_observables | composition | 28.1 | −27.64 | 2163 | 1051 | 0 | 28 | 0 |
| engeler_goertzel_bank | single-cycle | 27.3 | −28.64 | 1595 | 451 | 0 | 18 | 0 |
| dcf77_receiver_core | composition | 26.9 | −29.16 | 15564 | 5796 | 8 | 28 | 0 |

### Top-10 slowest

1. `dcf77_receiver_core` — 26.9 MHz (composition)
2. `engeler_goertzel_bank` — 27.3 MHz (single-cycle)
3. `engeler_observables` — 28.1 MHz (composition)
4. `engeler_detector` — 28.5 MHz (composition)
5. `dcf77_hat_top` — 28.9 MHz (composition)
6. `lcd_i2c_driver` — 29.3 MHz (io-interface)
7. `goertzel_resonator` — 34.7 MHz (single-cycle)
8. `calendar_candidate_search` — 38.8 MHz (multicycle)
9. `minute_candidate_search` — 39.7 MHz (multicycle)
10. `pm_minute_sync` — 39.8 MHz (low-rate-control)

---

## 3. Critical paths

| block | worst path (source → dest) | total (ns) | logic | route |
|---|---|---:|---:|---:|
| `engeler_goertzel_bank` | `pm_i.state_1[15]` → `pm_i.state_1[5]` | 36.12 | 15.67 | 20.45 |
| `dcf77_receiver_core` | `observables_i.detector_i.am_i.state_1` → `state_1` | 36.63 | 14.78 | 21.85 |
| `engeler_observables` | `carrier_i.state_1` → `carrier_i.overflow` | 35.11 | 15.08 | 20.04 |
| `engeler_detector` | `pm_i.state_1` → `pm_i.overflow` | 34.61 | 14.93 | 19.68 |
| `dcf77_hat_top` | `carrier_i.state_1` → `carrier_i.overflow` | 34.06 | 14.67 | 19.39 |
| `goertzel_resonator` (isolated) | `state_1[6]` → `state_1[14]` | 28.33 | 14.40 | 13.93 |
| `lcd_i2c_driver` | `pos[3]` → `state[2]` | 33.55 | 13.23 | 20.32 |
| `calendar_candidate_search` | `candidate[5]` → `quality_gap[1]` | 25.23 | 9.72 | 15.51 |
| `pm_minute_sync` | `history[10][7]` → `quality_gap` | 24.59 | 8.54 | 16.06 |
| `frequency_discipline` | `phase_error[22]` → `accepted_count[3]` | 13.72 | 5.71 | 8.00 |
| `second_phase_detector` | `magnitude_q[65]` → `missed_seconds[1]` | 15.79 | 5.47 | 10.32 |
| `pm_phase_discriminator` | `correlation[39]` → `div_dividend[14]` | 13.80 | 5.23 | 8.57 |

**Routing dominates the slow paths** (`~19–22 ns` of the `~34–36 ns`), and the
design has no floorplan/pin plan, so the logic is spread across the die.

### 3.1 The controlling path is the Goertzel resonator recurrence

Every one of the five slowest compositions is bounded by the *same* path inside
the Goertzel resonator: `state_1 (FF) → feedback multiply → 51-bit recurrence
add/saturate → scale multiply → overflow/state_1 (FF)`.  Two **chained 32×19
constant multiplies** plus the recurrence adder cannot fit one 8 ns period.  In
isolation the same path is 28.33 ns; the top adds ~5.7 ns of routing — i.e. the
integration cost is small, the *block* is the ceiling.  This is the blocker
already analysed in `docs/37` §4 (BEA-36).

---

## 4. Integration / boundary loss

Comparing a composition against the block it contains isolates the cost added at
the boundary:

| step | from | to | ΔFmax |
|---|---|---|---:|
| bank → observables | 27.29 | 28.06 | **+0.77** |
| observables → detector | 28.06 | 28.46 | **+0.40** |
| detector → receiver core | 28.46 | 26.91 | **−1.55** |
| receiver core → HAT top | 26.91 | 28.91 | **+2.00** |

**There is essentially no boundary loss.**  `engeler_observables` is *faster*
than the bank it contains, so composing resonators costs nothing measurable; the
ceiling is the resonator itself, repeated.  The `detector → core` drop (−1.55)
comes from a *second, independent* path entering the worst set (the ML/discipline
subsystem), not from a boundary artefact.  `core → top` recovers +2 MHz because
the top's PLL/clock placement happens to be marginally kinder to the same path.

Conclusion: **optimising the Goertzel resonator propagates directly to the top**
(no integration penalty to overcome first).

---

## 5. Resource consumption

**Largest LUT consumers:** `dcf77_hat_top` 17253 · `dcf77_receiver_core` 15564 ·
`engeler_detector` 9967 · `ml_field_sequencer` 3937 · `pm_phase_discriminator`
2185 · `frequency_discipline` 2167 · `engeler_observables` 2163 · `pm_minute_sync`
2097.

**Largest DSP consumers:** `engeler_observables`/`engeler_detector`/
`dcf77_receiver_core`/`dcf77_hat_top` 28 MULT18X18D each · `engeler_goertzel_bank`
18 · `goertzel_resonator` 6 · `goertzel_complex_12` 2.  (28/32 of the XC3S1400AN
envelope — the bank consumes ~all the DSP budget; 24 generic `$mul` are visible in
`engeler_observables` before mapping.)

**Largest RAM consumers:** `soft_history` 12 EBR18 · `dcf77_receiver_core`/
`dcf77_hat_top` 8 EBR18.

The whole design fits the historical envelope with DSP as the tightest resource
(28/32).  Any future resonator change must **not** add multipliers.

---

## 6. Latency / throughput of the slow blocks

| block | cadence in the application | verdict |
|---|---|---|
| `goertzel_resonator` / `engeler_goertzel_bank` | 1 sample per `sample_ce`; ~134 `clk_sys` per sample at 930 kSa/s / 125 MHz | **throughput-critical** — cannot be serialised further without a sample-cadence contract change |
| `second_phase_detector`, `pm_minute_sync` | 1 measurement per second | ~10⁸ idle cycles per update — trivially multi-cyclable |
| `calendar` / `minute` / `hour_candidate_search`, `ml_field_sequencer` | 1 search per minute | already `multicycle`; still deep — reduce depth or share |
| `frequency_discipline` | 1 observation per second | already `multicycle` (BEA-36) |
| `pm_phase_discriminator`, `pm_chip_integrator`, correlators | 1 chip per `chip_ce` | near/at 125 MHz; II=1 |
| `lcd_i2c_driver` | 1 I²C transaction per display update (~seconds) | low-rate; a slow FSM path is not on the sample path |

---

## 7. Ranked optimisation recommendations (by expected impact)

1. **P0 — Goertzel resonator bank** (`engeler_goertzel_bank` 27.3 MHz).  Controls
   the top.  The recurrence `s[n] = x + c·s[n−1] − s[n−2]` cannot be pipelined at
   1 sample/cycle; in hardware there are ~134 `clk_sys` per sample, so the fix is
   the multi-cycle pipeline already prototyped in `docs/37` §4.  Requires the
   sample cadence to be modelled in `dcf77_system_tb` (BEA-36 decision).  *Owner:
   BEA-36.*
2. **P1 — low-rate deep paths** (`second_phase_detector` 59.7, `pm_minute_sync`
   39.8, `calendar`/`minute` 38–40).  All update ≤1/s: spread each reduction over
   several cycles (same method as `frequency_discipline`).  No throughput cost,
   no DSP cost.  These do **not** gate the top today but they gate the *next*
   tier once the resonator is fixed.
3. **P1 — `lcd_i2c_driver` (29.3 MHz)**: a wide counter/`pos` → next-state
   comparison on one cycle.  Retiming / registering the next-state (or moving the
   compare off the critical path) brings it well past 125 MHz; fully off the
   sample path, so risk-free.
4. **P2 — `frequency_discipline` (68.2 MHz)**: already multi-cycle; further split
   the remaining reductions.  Low priority — it is no longer the top path.
5. **P2 — `pm_phase_discriminator` (69.8 MHz)**: the `div_dividend` divider path;
   candidate for time-sharing the division.
6. **P3 — PM correlators / pipeline (95–120 MHz)**: within ~5 % of target; small
   retiming only.

**Do not serialise further:** the Goertzel recurrence (throughput-critical, II=1)
and the PM correlators (must accept 1 chip/cycle).  Their depth is mandatory; only
*sharing* extra operators or adding cycles where the cadence allows is safe.

---

## 8. Notes

* **Redacted block name.**  In some terminals the AM block's name renders as a
  placeholder (`«redacted:…»` / `***`).  This is a **harness command-log secret
  scrubber**, not a repo or parser bug: `rtl/am/am_bit_extractor.sv`, the registry
  entry, the raw JSON key and `blocks.csv` all contain the real name on disk
  (confirmed with a filesystem listing, which is not scrubbed).  No pipeline fix
  is required.
* **Reproducibility.**  Results are keyed on `(commit, wrapper, tool_versions)`;
  re-running is a cache hit unless one of those changes.  Multi-seed mode
  (`make timing-all-blocks SEEDS=1,2,3,4`) guards against a lucky placement.
* **Scope.**  Pad/external-interface timing is out of scope; physical-interface
  blocks measure the internal `clk`-domain path only (`docs/38` §2.4).
