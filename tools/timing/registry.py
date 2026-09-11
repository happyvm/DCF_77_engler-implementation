"""Block and subsystem registry for the BEA-37 timing-characterisation campaign.

Every entry names a top module that can be elaborated on its own.  The
integration ladder already exists in the RTL hierarchy, so no synthetic
multi-instance compositions are needed::

    engeler_goertzel_bank  <  engeler_observables  <  engeler_detector
                           <  dcf77_receiver_core  <  dcf77_hat_top

``kind`` classifies the block for the timing-health report:

  single-cycle        one operation per clock enable; a path must close every cycle
  multicycle          architecture explicitly spreads an operation over N clocks
  low-rate-control    FSM/control updated far slower than clk_sys
  io-interface        physical interface; measurement is the internal clk path
  composition         hierarchical composition of other blocks
  primitive           vendor primitive / PLL; not meaningfully benchmarked in isolation

``latency`` and ``throughput`` are human-readable and kept deliberately coarse;
they exist so the report shows *why* a slow isolated path is or is not a
problem.  ``N/A`` is used explicitly when a value does not apply.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Bench:
    module: str
    file: str
    kind: str
    clock: str = "clk"
    latency: str = "N/A"
    throughput: str = "N/A"
    isolated: bool = True       # False => justified exception, no isolated wrapper
    direct: bool = False        # True => synthesize module as top (no wrapper), e.g. PLL top
    lpf: str | None = None      # LPF override for direct mode
    params: tuple[tuple[str, str], ...] = ()  # DUT param overrides for the benchmark
    notes: str = ""

    @property
    def param_dict(self) -> dict[str, str]:
        return dict(self.params)

    @property
    def config_label(self) -> str:
        return ", ".join(f"{k}={v}" for k, v in self.params) if self.params else "production-defaults"


BLOCKS: list[Bench] = [
    Bench("sample_scheduler", "rtl/core/sample_scheduler.sv", "low-rate-control",
          latency="1 clk (phase accumulator, sample_ce generated continuously)",
          throughput="1 sample_ce per 134 clk (930 kSa/s at 125 MHz)",
          notes="Rate generator; single accumulator add on the clk path."),
    Bench("adc_if", "rtl/platform/adc_if.sv", "io-interface",
          latency="N/A (serial frame FSM)",
          throughput="1 sample pair per frame (~32 clk)",
          notes="adc_sdo is an asynchronous serial input sampled by the clk FSM; "
                "adc_conv/adc_sck are output registers. Wrapper measures the clk-domain path only."),
    Bench("pga_spi_master", "rtl/platform/pga_spi_master.sv", "io-interface",
          latency="N/A (bit-banged SPI FSM)",
          throughput="1 gain word per SPI frame",
          notes="SPI clock is divided from clk; internal paths are clk-domain."),
    Bench("goertzel_resonator", "rtl/goertzel/goertzel_resonator.sv", "multicycle",
          latency="2 clk non-scale / 4 clk scale sample (GOERTZEL_MAX_CYCLES)",
          throughput="1 sample per >=4 clk (initiation interval; busy/done handshake)",
          notes="BEA-36 multi-cycle sequencer: one arithmetic reduction per cycle so no "
                "path carries two 32x19 multiplies. Real cadence is ~134 clk/sample."),
    Bench("goertzel_complex_12", "rtl/goertzel/goertzel_complex_12.sv", "single-cycle",
          latency="combinational (no clk use)",
          throughput="1 conversion per clk",
          notes="I/Q pair of combinatorially rotated states."),
    Bench("engeler_goertzel_bank", "rtl/goertzel/engeler_goertzel_bank.sv", "multicycle",
          latency="2 clk non-scale / 4 clk scale sample (GOERTZEL_MAX_CYCLES)",
          throughput="1 sample per >=4 clk (initiation interval; busy/done handshake)",
          notes="Carrier/AM/PM resonator bank; three multi-cycle sequencers in lockstep."),
    Bench("engeler_observables", "rtl/goertzel/engeler_observables.sv", "multicycle",
          latency="bank cycle_valid + 6 clk to observable_valid",
          throughput="1 sample per >=4 clk (initiation interval)",
          notes="Composition of engeler_goertzel_bank + three goertzel_complex_12; "
                "comparing with engeler_goertzel_bank alone shows the boundary cost."),
    Bench("am_bit_extractor", "rtl/am/am_bit_extractor.sv", "multicycle",
          latency="N/A (per-second decision)",
          throughput="1 AM bit per second",
          notes="Low-rate; a slow isolated path here is architecturally harmless."),
    Bench("dcf77_prn_generator", "rtl/pm/dcf77_prn_generator.sv", "low-rate-control",
          latency="N/A (chip sequence generator)",
          throughput="1 chip per CYCLES_PER_CHIP",
          notes="LFSR/sequence generator."),
    Bench("pm_prn_correlator", "rtl/pm/pm_prn_correlator.sv", "single-cycle",
          latency="1 clk per chip (II=1)",
          throughput="1 chip per clk (gated by chip_ce)",
          notes="Sign-multiply accumulate."),
    Bench("engeler_pm_correlator", "rtl/pm/engeler_pm_correlator.sv", "single-cycle",
          latency="1 clk per chip (II=1)",
          throughput="1 chip per clk (gated by chip_ce)",
          notes="PM soft multiply-accumulate."),
    Bench("pm_chip_integrator", "rtl/pm/pm_chip_integrator.sv", "multicycle",
          latency="N/A (integration window)",
          throughput="1 correlation per chip window",
          notes="Accumulator over the PRN sequence."),
    Bench("engeler_pm_pipeline", "rtl/pm/engeler_pm_pipeline.sv", "composition",
          latency="correlator depth + integrator depth",
          throughput="1 chip per clk (chip_ce)",
          notes="Composition of pm_chip_integrator + correlators."),
    Bench("pm_phase_discriminator", "rtl/pm/pm_phase_discriminator.sv", "composition",
          latency="2x pipeline depth (early/late)",
          throughput="1 result per PRN cycle",
          notes="Instantiates two engeler_pm_pipeline (early + late)."),
    Bench("second_phase_detector", "rtl/sync/second_phase_detector.sv", "low-rate-control",
          latency="N/A (per-second edge detection)",
          throughput="1 measurement per second",
          notes="Carrier-ce rate path; once-per-second update."),
    Bench("pm_minute_sync", "rtl/sync/pm_minute_sync.sv", "low-rate-control",
          latency="N/A (pattern match)",
          throughput="1 result per second",
          notes="Begin-of-minute pattern search."),
    Bench("second_evidence_aggregator", "rtl/ml_decoder/second_evidence_aggregator.sv", "single-cycle",
          latency="1 clk per second (II=1)",
          throughput="1 per second",
          notes="Per-second AM/PM soft aggregation."),
    Bench("soft_history", "rtl/ml_decoder/soft_history.sv", "multicycle",
          latency="read latency after read_enable",
          throughput="1 write/read per second",
          notes="3600-deep EBR-backed history; representative EBR configuration preserved."),
    Bench("ml_field_sequencer", "rtl/ml_decoder/ml_field_sequencer.sv", "composition",
          latency="minute + hour + calendar search depth",
          throughput="1 decode per minute",
          notes="Composition of minute/hour/calendar candidate searches."),
    Bench("minute_candidate_search", "rtl/ml_decoder/minute_candidate_search.sv", "multicycle",
          latency="N clk (score accumulation over candidate set)",
          throughput="1 search per minute",
          notes="Search FSM; several cycles per candidate are architecturally allowed."),
    Bench("hour_candidate_search", "rtl/ml_decoder/hour_candidate_search.sv", "multicycle",
          latency="N clk (score accumulation)",
          throughput="1 search per hour boundary",
          notes="Search FSM."),
    Bench("calendar_candidate_search", "rtl/ml_decoder/calendar_candidate_search.sv", "multicycle",
          latency="N clk (score accumulation)",
          throughput="1 search per minute boundary",
          notes="Search FSM; owned by BEA-36 for timing closure."),
    Bench("ml_decoder_controller", "rtl/ml_decoder/ml_decoder_controller.sv", "low-rate-control",
          latency="N/A (frame continuity FSM)",
          throughput="1 decision per minute",
          notes="Control path."),
    Bench("receiver_lock_controller", "rtl/control/receiver_lock_controller.sv", "low-rate-control",
          latency="N/A (lock FSM)",
          throughput="1 transition per event",
          params=(("QUALIFICATION_ENABLED", "1'b1"),),
          notes="Control path. Benchmark uses QUALIFICATION_ENABLED=1: the production "
                "default 0 forces UNSYNC and folds the whole FSM to an empty design, "
                "so the enabled configuration is the meaningful one to time."),
    Bench("frequency_discipline", "rtl/clock_discipline/frequency_discipline.sv", "multicycle",
          latency="1 clk observation, once per second (see BEA-36)",
          throughput="1 correction per measurement_ce intervals",
          notes="PI loop; extremely slow relative to clk_sys, a candidate for multi-cycle sharing."),
    Bench("pps_generator", "rtl/core/pps_generator.sv", "low-rate-control",
          latency="N/A (pulse counter)",
          throughput="1 PPS per second",
          notes="Counter compare."),
    Bench("pps_uart", "rtl/core/pps_uart.sv", "composition",
          latency="N/A",
          throughput="1 PPS + telemetry per second",
          notes="Composition of pps_generator + time_telemetry + uart_tx."),
    Bench("time_telemetry", "rtl/core/time_telemetry.sv", "low-rate-control",
          latency="N/A (frame formatter)",
          throughput="1 frame per second",
          notes="UART frame builder."),
    Bench("uart_tx", "rtl/platform/uart_tx.sv", "io-interface",
          latency="1 start bit (1 clk)",
          throughput="1 byte per (CLK_HZ/BAUD) clk",
          notes="Bit serializer."),
    Bench("hat_spi_slave", "rtl/platform/hat_spi_slave.sv", "io-interface",
          latency="N/A (SPI transaction FSM)",
          throughput="1 register access per SPI frame",
          notes="spi_sclk is an external serial clock sampled by the clk FSM."),
    Bench("lcd_i2c_driver", "rtl/platform/lcd_i2c_driver.sv", "io-interface",
          latency="N/A (I2C transaction FSM)",
          throughput="1 I2C transaction per display update",
          notes="Bit-banged I2C; scl/sda output registers."),
    Bench("i2c_master_byte", "rtl/platform/i2c_master_byte.sv", "io-interface",
          latency="N/A (byte engine FSM)",
          throughput="1 byte per I2C frame",
          notes="Byte engine used by the LCD driver."),
    # ---- composed blocks benchmarked as part of the ladder ----
    Bench("engeler_detector", "rtl/core/engeler_detector.sv", "composition",
          latency="stage sum (observables + AM + PM + sync)",
          throughput="1 sample per clk (sample_ce)",
          notes="Goertzel + observables + AM + PM + second/minute sync."),
    Bench("dcf77_receiver_core", "rtl/core/dcf77_receiver_core.sv", "composition",
          latency="whole-pipeline latency",
          throughput="1 sample per clk (sample_ce)",
          notes="Detector + ML decode + discipline + lock + PPS/UART."),
    Bench("dcf77_hat_top", "rtl/top/dcf77_hat_top.sv", "composition",
          isolated=False, direct=True, lpf="synth/dcf77_hat_top.lpf", clock="clk_25m",
          latency="whole-system latency",
          throughput="1 sample per clk at 125 MHz (PLL-derived)",
          notes="Full HAT top; contains the ECP5 PLL, benchmarked in direct mode with the "
                "production LPF (clk_25m 25 MHz -> clk 125 MHz)."),
    Bench("clock_reset_ecp5", "rtl/ecp5/clock_reset_ecp5.sv", "primitive",
          isolated=False, clock="clk_25m",
          notes="EXCEPTION: PLL + reset primitive. nextpnr times the EHXPLLL hard macro, "
                "not a clk-domain register path; measured through dcf77_hat_top instead."),
    Bench("dcf77_calendar_pkg", "rtl/ml_decoder/dcf77_calendar_pkg.sv", "primitive",
          isolated=False, notes="EXCEPTION: SystemVerilog package, not a module."),
]

# Subsystems reuse the module results (same wrapper, same netlist) so the report
# is generated from a single real place-and-route per module.
SUBSYSTEMS: dict[str, str] = {
    "goertzel_observables": "engeler_observables",
    "receiver_dsp_core": "engeler_detector",
    "ml_decode_subsystem": "ml_field_sequencer",
    "frequency_discipline_subsystem": "frequency_discipline",
    "full_receiver_core": "dcf77_receiver_core",
    "full_hat_top": "dcf77_hat_top",
}

_BY_MODULE = {b.module: b for b in BLOCKS}


def get_block(module: str) -> Bench:
    try:
        return _BY_MODULE[module]
    except KeyError:
        raise SystemExit(
            f"unknown block {module!r}; known: {', '.join(sorted(_BY_MODULE))}"
        )


def isolated_blocks() -> list[Bench]:
    return [b for b in BLOCKS if b.isolated]


def is_block_name(name: str) -> bool:
    return name in _BY_MODULE


# The RTL file set elaborated for every benchmark.  ``hierarchy -top`` prunes
# everything the wrapper does not need, so using one shared list keeps the
# Yosys invocation identical across blocks (same options => comparable results).
ALL_RTL = [
    "rtl/ecp5/clock_reset_ecp5.sv",
    "rtl/platform/*.sv",
    "rtl/goertzel/*.sv",
    "rtl/am/*.sv",
    "rtl/pm/*.sv",
    "rtl/sync/*.sv",
    "rtl/ml_decoder/*.sv",
    "rtl/control/*.sv",
    "rtl/clock_discipline/*.sv",
    "rtl/core/*.sv",
    "rtl/top/dcf77_hat_top.sv",
]
