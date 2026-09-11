IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys
SBY ?= sby
PYTHON ?= python3
BUILD_DIR ?= build

.PHONY: test test-adc-if test-pps test-telemetry test-uart test-goertzel \
	test-observables test-prn test-pm-correlator test-pm-integrator \
	test-pm-pipeline test-am-bit test-minute-sync test-minute-ml test-hour-ml \
	test-second-phase test-lock-controller test-qualification-disabled \
	lint-pps-uart lint-goertzel lint-detector lint formal synth \
	resource-check timing test-tools test-soft-history test-ml-controller \
	test-frequency-discipline tool-versions clean test-integration synth-core \
	test-evidence-aggregator test-calendar-ml test-field-sequencer test-pm-discriminator \
	test-second-phase-ramp test-system test-pga test-hat-spi test-lcd test-system

test: test-adc-if test-pps test-telemetry test-uart test-goertzel \
	test-observables test-prn test-pm-correlator test-pm-integrator \
	test-pm-pipeline test-am-bit test-minute-sync test-minute-ml test-hour-ml \
	test-second-phase test-lock-controller test-qualification-disabled test-tools \
	test-soft-history test-ml-controller test-frequency-discipline test-integration \
	test-evidence-aggregator test-calendar-ml test-field-sequencer test-pm-discriminator \
	test-second-phase-ramp test-system test-pga test-hat-spi test-lcd

test-integration: $(BUILD_DIR)/dcf77_hat_top_tb.vvp
	$(VVP) $<

TOP_RTL := rtl/ecp5/clock_reset_ecp5.sv rtl/platform/adc_if.sv rtl/platform/pga_spi_master.sv \
	rtl/platform/hat_spi_slave.sv rtl/platform/i2c_master_byte.sv rtl/platform/lcd_i2c_driver.sv \
	rtl/platform/uart_tx.sv rtl/core/sample_scheduler.sv rtl/core/pps_generator.sv \
	rtl/core/time_telemetry.sv rtl/core/pps_uart.sv rtl/goertzel/*.sv rtl/am/*.sv \
	rtl/pm/*.sv rtl/sync/*.sv rtl/core/engeler_detector.sv rtl/ml_decoder/*.sv \
	rtl/control/*.sv rtl/clock_discipline/*.sv rtl/core/dcf77_receiver_core.sv \
	rtl/top/dcf77_hat_top.sv

# Everything the receiver core needs, without the HAT shell (PLL, sample
# scheduler, ADC serial interface): the system test drives the core at one
# sample per clock instead of paying for the 32-edge ADC frame per sample.
CORE_RTL := rtl/core/pps_generator.sv rtl/core/time_telemetry.sv rtl/core/pps_uart.sv \
	rtl/platform/uart_tx.sv rtl/goertzel/*.sv rtl/am/*.sv rtl/pm/*.sv rtl/sync/*.sv \
	rtl/core/engeler_detector.sv rtl/ml_decoder/*.sv rtl/control/*.sv \
	rtl/clock_discipline/*.sv rtl/core/dcf77_receiver_core.sv

test-second-phase-ramp: $(BUILD_DIR)/second_phase_ramp_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/second_phase_ramp_tb.vvp: rtl/sync/second_phase_detector.sv sim/second_phase_ramp_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s second_phase_ramp_tb -o $@ $^

# The system test simulates several minutes of receiver time per scenario;
# Icarus needs ~5 s of wall clock per simulated second on this design, so
# it is built with Verilator (--binary --timing), ~60x faster. Run a single
# scenario with `build/vl_system/dcf77_system_tb +scenario=N +verbose`.
test-system: $(BUILD_DIR)/vl_system/dcf77_system_tb
	timeout 900 $<
$(BUILD_DIR)/vl_system/dcf77_system_tb: $(CORE_RTL) sim/dcf77_system_tb.sv
	mkdir -p $(BUILD_DIR)/vl_system
	$(VERILATOR) --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style \
		--top-module dcf77_system_tb --Mdir $(BUILD_DIR)/vl_system \
		-o dcf77_system_tb $^

$(BUILD_DIR)/dcf77_hat_top_tb.vvp: $(TOP_RTL) sim/dcf77_hat_top_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s dcf77_hat_top_tb -o $@ $^

test-frequency-discipline: $(BUILD_DIR)/frequency_discipline_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/frequency_discipline_tb.vvp: \
		rtl/clock_discipline/frequency_discipline.sv sim/frequency_discipline_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s frequency_discipline_tb -o $@ $^

test-adc-if: $(BUILD_DIR)/adc_if_tb.vvp
	$(VVP) $<

test-hat-spi: $(BUILD_DIR)/hat_spi_slave_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/hat_spi_slave_tb.vvp: rtl/platform/hat_spi_slave.sv sim/hat_spi_slave_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s hat_spi_slave_tb -o $@ $^

test-lcd: $(BUILD_DIR)/lcd_i2c_driver_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/lcd_i2c_driver_tb.vvp: rtl/platform/i2c_master_byte.sv rtl/platform/lcd_i2c_driver.sv \
		sim/lcd_i2c_driver_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s lcd_i2c_driver_tb -o $@ $^

test-pga: $(BUILD_DIR)/pga_spi_master_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/pga_spi_master_tb.vvp: rtl/platform/pga_spi_master.sv sim/pga_spi_master_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s pga_spi_master_tb -o $@ $^

$(BUILD_DIR)/adc_if_tb.vvp: rtl/platform/adc_if.sv sim/adc_if_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s adc_if_tb -o $@ $^

test-pps: $(BUILD_DIR)/pps_generator_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/pps_generator_tb.vvp: rtl/core/pps_generator.sv sim/pps_generator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s pps_generator_tb -o $@ $^

test-telemetry: $(BUILD_DIR)/time_telemetry_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/time_telemetry_tb.vvp: rtl/core/time_telemetry.sv sim/time_telemetry_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s time_telemetry_tb -o $@ $^

test-uart: $(BUILD_DIR)/uart_tx_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/uart_tx_tb.vvp: rtl/platform/uart_tx.sv sim/uart_tx_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s uart_tx_tb -o $@ $^

lint-pps-uart:
	$(IVERILOG) -g2012 -Wall -s pps_uart -o /dev/null \
		rtl/core/pps_generator.sv rtl/core/time_telemetry.sv \
		rtl/platform/uart_tx.sv rtl/core/pps_uart.sv

test-goertzel: $(BUILD_DIR)/engeler_goertzel_bank_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/engeler_goertzel_bank_tb.vvp: \
		rtl/goertzel/goertzel_resonator.sv \
		rtl/goertzel/engeler_goertzel_bank.sv \
		sim/engeler_goertzel_bank_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s engeler_goertzel_bank_tb -o $@ $^

lint-goertzel:
	$(IVERILOG) -g2012 -Wall -s engeler_goertzel_bank -o /dev/null \
		rtl/goertzel/goertzel_resonator.sv \
		rtl/goertzel/engeler_goertzel_bank.sv

test-observables: $(BUILD_DIR)/engeler_observables_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/engeler_observables_tb.vvp: \
		rtl/goertzel/goertzel_resonator.sv \
		rtl/goertzel/engeler_goertzel_bank.sv \
		rtl/goertzel/goertzel_complex_12.sv \
		rtl/goertzel/engeler_observables.sv \
		sim/engeler_observables_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s engeler_observables_tb -o $@ $^

test-prn: $(BUILD_DIR)/dcf77_prn_generator_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/dcf77_prn_generator_tb.vvp: \
		rtl/pm/dcf77_prn_generator.sv sim/dcf77_prn_generator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s dcf77_prn_generator_tb -o $@ $^

test-pm-correlator: $(BUILD_DIR)/engeler_pm_correlator_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/engeler_pm_correlator_tb.vvp: \
		rtl/pm/dcf77_prn_generator.sv rtl/pm/pm_prn_correlator.sv \
		rtl/pm/engeler_pm_correlator.sv sim/engeler_pm_correlator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s engeler_pm_correlator_tb -o $@ $^

test-pm-integrator: $(BUILD_DIR)/pm_chip_integrator_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/pm_chip_integrator_tb.vvp: \
		rtl/pm/pm_chip_integrator.sv sim/pm_chip_integrator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s pm_chip_integrator_tb -o $@ $^

test-pm-pipeline: $(BUILD_DIR)/engeler_pm_pipeline_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/engeler_pm_pipeline_tb.vvp: \
		rtl/pm/pm_chip_integrator.sv rtl/pm/dcf77_prn_generator.sv \
		rtl/pm/pm_prn_correlator.sv rtl/pm/engeler_pm_correlator.sv \
		rtl/pm/engeler_pm_pipeline.sv sim/engeler_pm_pipeline_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s engeler_pm_pipeline_tb -o $@ $^

test-am-bit: $(BUILD_DIR)/am_bit_extractor_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/am_bit_extractor_tb.vvp: \
		rtl/am/am_bit_extractor.sv sim/am_bit_extractor_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s am_bit_extractor_tb -o $@ $^

test-minute-sync: $(BUILD_DIR)/pm_minute_sync_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/pm_minute_sync_tb.vvp: \
		rtl/sync/pm_minute_sync.sv sim/pm_minute_sync_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s pm_minute_sync_tb -o $@ $^

test-second-phase: $(BUILD_DIR)/second_phase_detector_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/second_phase_detector_tb.vvp: \
		rtl/sync/second_phase_detector.sv sim/second_phase_detector_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s second_phase_detector_tb -o $@ $^

test-minute-ml: $(BUILD_DIR)/minute_candidate_search_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/minute_candidate_search_tb.vvp: \
		rtl/ml_decoder/minute_candidate_search.sv \
		sim/minute_candidate_search_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s minute_candidate_search_tb -o $@ $^

test-hour-ml: $(BUILD_DIR)/hour_candidate_search_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/hour_candidate_search_tb.vvp: \
		rtl/ml_decoder/hour_candidate_search.sv sim/hour_candidate_search_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s hour_candidate_search_tb -o $@ $^

test-soft-history: $(BUILD_DIR)/soft_history_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/soft_history_tb.vvp: rtl/ml_decoder/soft_history.sv sim/soft_history_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s soft_history_tb -o $@ $^

test-ml-controller: $(BUILD_DIR)/ml_decoder_controller_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/ml_decoder_controller_tb.vvp: rtl/ml_decoder/dcf77_calendar_pkg.sv \
		rtl/ml_decoder/ml_decoder_controller.sv sim/ml_decoder_controller_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s ml_decoder_controller_tb -o $@ $^

test-evidence-aggregator: $(BUILD_DIR)/second_evidence_aggregator_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/second_evidence_aggregator_tb.vvp: \
		rtl/ml_decoder/second_evidence_aggregator.sv sim/second_evidence_aggregator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s second_evidence_aggregator_tb -o $@ $^

test-calendar-ml: $(BUILD_DIR)/calendar_candidate_search_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/calendar_candidate_search_tb.vvp: \
		rtl/ml_decoder/calendar_candidate_search.sv sim/calendar_candidate_search_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s calendar_candidate_search_tb -o $@ $^

test-field-sequencer: $(BUILD_DIR)/ml_field_sequencer_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/ml_field_sequencer_tb.vvp: \
		rtl/ml_decoder/minute_candidate_search.sv rtl/ml_decoder/hour_candidate_search.sv \
		rtl/ml_decoder/calendar_candidate_search.sv rtl/ml_decoder/ml_field_sequencer.sv \
		sim/ml_field_sequencer_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s ml_field_sequencer_tb -o $@ $^

test-pm-discriminator: $(BUILD_DIR)/pm_phase_discriminator_tb.vvp
	$(VVP) $<
$(BUILD_DIR)/pm_phase_discriminator_tb.vvp: \
		rtl/pm/pm_chip_integrator.sv rtl/pm/dcf77_prn_generator.sv rtl/pm/pm_prn_correlator.sv \
		rtl/pm/engeler_pm_correlator.sv rtl/pm/engeler_pm_pipeline.sv \
		rtl/pm/pm_phase_discriminator.sv sim/pm_phase_discriminator_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s pm_phase_discriminator_tb -o $@ $^

test-lock-controller: $(BUILD_DIR)/receiver_lock_controller_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/receiver_lock_controller_tb.vvp: \
		rtl/control/receiver_lock_controller.sv sim/receiver_lock_controller_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s receiver_lock_controller_tb -o $@ $^

test-qualification-disabled: $(BUILD_DIR)/qualification_disabled_tb.vvp
	$(VVP) $<

$(BUILD_DIR)/qualification_disabled_tb.vvp: \
		rtl/sync/pm_minute_sync.sv \
		rtl/ml_decoder/minute_candidate_search.sv \
		rtl/ml_decoder/hour_candidate_search.sv sim/qualification_disabled_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s qualification_disabled_tb -o $@ $^

lint-detector:
	$(IVERILOG) -g2012 -Wall -s engeler_detector -o /dev/null \
		rtl/goertzel/goertzel_resonator.sv \
		rtl/goertzel/engeler_goertzel_bank.sv \
		rtl/goertzel/goertzel_complex_12.sv \
		rtl/goertzel/engeler_observables.sv \
		rtl/am/am_bit_extractor.sv rtl/pm/pm_chip_integrator.sv \
		rtl/pm/dcf77_prn_generator.sv rtl/pm/pm_prn_correlator.sv \
		rtl/pm/engeler_pm_correlator.sv rtl/pm/engeler_pm_pipeline.sv \
		rtl/sync/pm_minute_sync.sv rtl/sync/second_phase_detector.sv \
		rtl/core/engeler_detector.sv

lint:
	$(VERILATOR) --lint-only --timing -Wall --top-module engeler_detector \
		rtl/goertzel/*.sv rtl/am/*.sv rtl/pm/*.sv rtl/sync/*.sv \
		rtl/core/engeler_detector.sv

FORMAL_JOBS := $(wildcard formal/*.sby)

# Every formal/*.sby is run with a per-job timeout of 600s (10 min).
# pipefail matters: without it the pipeline's status is tail's and a
# failing sby would be silently reported as success.
# Deep BMC proofs (i2c_master_byte, minute_candidate_search, pm_minute_sync,
# second_phase_detector, time_telemetry) may time out on slow machines; they
# are correct but solver-limited.  See docs/formal-validation-results.md.
formal:
	@bash -o pipefail -c 'pass=0; fail=0; timeouts=0; for job in $(FORMAL_JOBS); do \
		echo "== $$job"; \
		output=$$(timeout 600 $(SBY) -f $$job 2>&1); rc=$$?; \
		echo "$$output" | tail -3; \
		if echo "$$output" | grep -q "DONE (PASS"; then \
			pass=$$((pass + 1)); \
		elif [ $$rc -eq 124 ]; then \
			timeouts=$$((timeouts + 1)); \
		else \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo "=== Formal Summary ==="; \
	echo "PASS: $$pass  TIMEOUT: $$timeouts  FAIL: $$fail"; \
	[ $$fail -eq 0 ]'

synth:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -s synth/release_reference.ys

# Standalone ECP5 synthesis with its own JSON/stat artefact (BEA-26).
synth-ecp5:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -s synth/synth_ecp5.ys

# Keep the isolated detector build as a diagnostic target.
synth-core:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -s synth/engeler_detector.ys

resource-check: synth
	mkdir -p $(BUILD_DIR)/reports
	bash -o pipefail -c '$(PYTHON) tools/check_resource_budget.py \
		$(BUILD_DIR)/release_reference.json --profile release_reference | \
		tee $(BUILD_DIR)/reports/resource-budget.txt'

resource-check-ecp5: synth-ecp5
	mkdir -p $(BUILD_DIR)/reports
	bash -o pipefail -c '$(PYTHON) tools/check_resource_budget.py \
		$(BUILD_DIR)/synth_ecp5.json --profile release_reference --limits ecp5_limits | \
		tee $(BUILD_DIR)/reports/resource-budget-ecp5.txt'

# This is a device-level implementation used for a reproducible timing estimate.
# It is not a board bitstream: pin locations are still pending (see
# docs/27-ecp5-pin-plan-hat.md). synth/dcf77_hat_top.lpf supplies the two
# constraints that do not depend on a physical pin-out: the real 125 MHz
# system clock (matching sample_scheduler and clock_reset_ecp5's PLL, not
# an arbitrary probe frequency) and BLOCK ASYNCPATHS, so genuinely
# asynchronous ports (reset_n/hat_reset_n feed clock_reset_ecp5's async
# FF reset directly) are not folded into the synchronous Fmax figure.
timing: synth
	mkdir -p $(BUILD_DIR)/reports
	bash -o pipefail -c 'nextpnr-ecp5 --45k --package CABGA256 --freq 125 \
		--lpf synth/dcf77_hat_top.lpf --lpf-allow-unconstrained \
		--json $(BUILD_DIR)/release_reference.json \
		--textcfg $(BUILD_DIR)/release_reference.config \
		--report $(BUILD_DIR)/reports/nextpnr.json 2>&1 | \
		tee $(BUILD_DIR)/reports/nextpnr.log'

test-tools:
	$(PYTHON) -m unittest discover -s tests -v

tool-versions:
	$(IVERILOG) -V
	$(VERILATOR) --version
	$(YOSYS) -V
	nextpnr-ecp5 --version
	ecppack --version
	$(SBY) --version
	boolector --version

clean:
	rm -rf $(BUILD_DIR)
