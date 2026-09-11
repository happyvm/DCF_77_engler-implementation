# AGENTS.md — DCF77 Engler FPGA Receiver

Guidance for AI agents working in this repository.

## Critical Rules

⚠️ **COMMIT + PUSH est une seule opération atomique.**
Tu ne fais JAMAIS `git commit` sans `git push origin main` immédiatement après.

## Stack

- RTL: SystemVerilog (IEEE 1800-2012)
- Target FPGA: Lattice ECP5 LFE5U-45F-7BG256I
- Reference FPGA: Xilinx XC3S1400AN (historical resource envelope)
- Simulation: Icarus Verilog 12.0, Verilator
- Formal: SymbiYosys (sby)
- Synthesis: Yosys 0.52 (synth_ecp5)
- Hardware CAD: tscircuit (TypeScript), KiCad export
- Python tools: resource budget checker, clock plan, PRN generator

## RTL Structure

```
rtl/
  top/           — top-level integration
  am/            — amplitude demodulation
  pm/            — phase modulation correlator (PRN)
  goertzel/       — Goertzel filter bank
  sync/           — second/minute sync
  ml_decoder/     — maximum likelihood time decoder
  clock_discipline/ — SI5356 frequency discipline
  core/           — detector core, sample scheduler
  control/        — receiver lock controller
  platform/       — ADC interface, SPI, I2C, UART, LCD, HAT SPI slave
```

## Rules

1. **Tout test doit passer avant commit.** `make test-<module>` ou `make test` selon la portée.
2. **Respecter le resource budget.** `python3 tests/test_resource_budget.py` avant commit.
3. **Conventional commits:** feat:, fix:, refactor:, docs:, test:
4. **Pas de réinvention.** Le `docs/` contient 30+ fichiers de design. Lis avant de coder.
5. **Preuves formelles.** Si tu modifies un module avec un `.sby`, relance `sby -f formal/<module>.sby`.
6. **Tout RTL compile avec `iverilog -g2012 -Wall`.** Pas de warning non documenté.
7. **Push atomique.** `git commit` → `git push origin main`.
8. **File locking — un seul ticket par fichier à la fois.** Avant de modifier un fichier RTL, vérifie qu'aucun AUTRE ticket `in_progress` ne travaille dessus :
   - `GET /api/companies/{companyId}/issues?status=in_progress` → liste les tickets actifs
   - si un autre ticket touche le même module (visible dans ses commentaires), NE PAS y toucher
   - bloquer son propre ticket avec `blockedByIssueIds: [<ticket qui détient le module>]` et nommer l'owner
   - jamais deux agents ne doivent éditer le même module dans le même cycle — ça corrompt les diffs
   - cas typique à risque ici : `rtl/core/engeler_detector.sv`, `rtl/pm/*.sv` (BEA-25 formel + BEA-28 MULT touchent les mêmes blocs)

## Toolchain

```bash
# Simulation unitaire
make test-adc-if

# Suite complète
make test

# Synthèse ECP5
yosys -s synth/synth_ecp5.ys

# Preuve formelle
sby -f formal/goertzel_resonator.sby
```

## Documents clés

- `README.md` — architecture, signal chain, Rev.0 board
- `docs/08-reconstruction-plan.md` — plan global
- `docs/09-gaps-and-open-questions.md` — DSP constants à résoudre
- `docs/10-dcf77-pm-prn.md` — PRN generator spec
- `docs/12-ecp5-migration.md` — migration Xilinx → ECP5
- `docs/16-fpga-resource-budget.md` — budget ressources
- `archive/papers/Engeler_DCF77.pdf` — papier original
- `rtl/resource_budget.json` — budget LUT/FF/BRAM/MULT

## DSP Gaps (priority)

Les constantes DSP manquantes (voir `docs/09-gaps-and-open-questions.md` §Missing DSP constants) doivent être résolues par simulation + régression:

1. fixed-point word widths
2. Goertzel scaling
3. carrier-loop bandwidth schedule
4. CORDIC precision if used
5. AGC thresholds/time constants
6. correlation normalization
7. ML confidence thresholds
8. overflow/saturation policy
9. memory organization
10. randomized-processing schedule

Méthode: simuler chaque bloc avec iverilog, comparer avec le papier Engeler, itérer.