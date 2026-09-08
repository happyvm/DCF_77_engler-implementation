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
	resource-check timing test-tools tool-versions clean

test: test-adc-if test-pps test-telemetry test-uart test-goertzel \
	test-observables test-prn test-pm-correlator test-pm-integrator \
	test-pm-pipeline test-am-bit test-minute-sync test-minute-ml test-hour-ml \
	test-second-phase test-lock-controller test-qualification-disabled test-tools

test-adc-if: $(BUILD_DIR)/adc_if_tb.vvp
	$(VVP) $<

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

formal:
	$(SBY) -f formal/pps_generator.sby

synth:
	mkdir -p $(BUILD_DIR)
	$(YOSYS) -s synth/engeler_detector.ys

resource-check: synth
	mkdir -p $(BUILD_DIR)/reports
	bash -o pipefail -c '$(PYTHON) tools/check_resource_budget.py \
		$(BUILD_DIR)/engeler_detector.json --profile release_reference | \
		tee $(BUILD_DIR)/reports/resource-budget.txt'

# This is a device-level implementation used for a reproducible timing estimate.
# It is not a board bitstream: pin and board clock constraints are still pending.
timing: synth
	mkdir -p $(BUILD_DIR)/reports
	bash -o pipefail -c 'nextpnr-ecp5 --45k --package CABGA256 --freq 48 \
		--json $(BUILD_DIR)/engeler_detector.json \
		--textcfg $(BUILD_DIR)/engeler_detector.config \
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
