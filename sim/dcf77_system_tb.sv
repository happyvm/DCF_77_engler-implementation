`timescale 1ns/1ps
// End-to-end synthetic-signal system test.
//
// Drives dcf77_receiver_core with a physically-modeled DCF77 AM+PM carrier
// -- 100/200 ms amplitude reduction per telegram bit, the 15-second PM
// minute-marker polarity pattern followed by data polarity, a 512-chip
// BPSK burst from 200 ms to ~993 ms of every second, all riding one
// 12-samples-per-cycle carrier the Goertzel front end is tuned for (see
// docs/31-goertzel-rtl.md) -- and checks the receiver's own decoded civil
// time against the telegram actually transmitted, through the real chain:
// engeler_detector (AM/PM evidence, second sync, PZF discriminator) ->
// soft_history -> ml_field_sequencer/ml_decoder_controller ->
// receiver_lock_controller -> pps_uart. A noise-only run must never publish.
//
// Time compression: every carrier-cycle constant is shortened by SCALE and
// the Goertzel bins widened by the same factor, so one DCF77 second costs
// SECOND_CYCLES*12 clocks instead of 930k. The sample scheduler and ADC
// serial interface are not in this path (they have their own tests); the
// core sees one sample per clock. CONSISTENT_FRAMES/ACQUIRE_RESULTS are 1
// so a scenario needs a few simulated minutes, not many; every MIN_SCORE/
// MIN_GAP/quality threshold stays at its real default.
module dcf77_system_tb;
    import dcf77_calendar_pkg::*;

    localparam int SCALE = 10;
    localparam int SECOND_CYCLES    = 77_500 / SCALE;
    localparam int AM_WINDOW        = SECOND_CYCLES / 10;
    localparam int PRN_START_CYCLE  = SECOND_CYCLES / 5;
    localparam int CYCLES_PER_CHIP  = 120 / SCALE;
    localparam int CHIP_COUNT       = 512;
    // 1-k scaled by SCALE for each bin (Q1.17, see engeler_goertzel_bank).
    localparam logic signed [18:0] CARRIER_SCALE = 19'sd131072 - 19'sd13   * SCALE;
    localparam logic signed [18:0] AM_SCALE      = 19'sd131072 - 19'sd79   * SCALE;
    localparam logic signed [18:0] PM_SCALE      = 19'sd131072 - 19'sd4915 * SCALE;
    localparam real PI = 3.14159265358979323846;
    localparam real FULL_AMPLITUDE = 6000.0;
    localparam real REDUCED_AMPLITUDE = 1500.0;
    localparam real PM_DEVIATION = 0.35; // radians, ~20 degrees

    logic clk = 1'b0, rst = 1'b1;
    always #4 clk = ~clk;

    logic sample_ce = 1'b0;
    logic signed [13:0] sample = 14'sd0;
    logic signed [23:0] trim_inc;
    logic second_ce, time_valid, pps_valid, detector_overflow, minute_result_valid;
    logic [5:0] second_number; logic [2:0] lock_state; logic [7:0] phase_quality;
    logic [5:0] decoded_minute; logic [4:0] decoded_hour; logic [5:0] decoded_day;
    logic [2:0] decoded_weekday; logic [3:0] decoded_month; logic [7:0] decoded_year;
    logic decoded_cest, uart_tx, pps, pps_ref, telemetry_done;

    dcf77_receiver_core #(
        .SECOND_CYCLES(SECOND_CYCLES),
        .SECOND_SEARCH_TOLERANCE(1_000 / SCALE), .SECOND_TRACK_WINDOW(2_000 / SCALE),
        .SECOND_ACQUIRE_HITS(2),
        .CYCLES_PER_CHIP(CYCLES_PER_CHIP), .CHIP_COUNT(CHIP_COUNT),
        .CARRIER_SCALE(CARRIER_SCALE), .AM_SCALE(AM_SCALE), .PM_SCALE(PM_SCALE),
        .PPS_PULSE_CYCLES(200), .HISTORY_DEPTH(96),
        .QUALIFICATION_ENABLED(1'b1),
        .CONSISTENT_FRAMES(1), .ACQUIRE_RESULTS(1), .EXIT_FAILURES(1),
        .HOLDOVER_ENABLED(1'b1), .HOLDOVER_TICKS(5)
    ) dut (.*);

    logic telemetry_seen = 1'b0, pps_seen = 1'b0;
    always @(posedge clk) begin
        if (telemetry_done) telemetry_seen <= 1'b1;
        if (pps) pps_seen <= 1'b1;
    end

    // --- Synthetic signal generator state ---------------------------------
    integer sample_in_cycle = 0;   // 0..11, position within a carrier cycle
    integer carrier_cycle   = 0;   // 0..SECOND_CYCLES-1
    integer second_in_min   = 0;   // 0..59
    integer minutes_sent    = 0;
    integer chip_index      = -1;  // -1 when outside the PRN burst
    logic [8:0] ref_lfsr    = 9'b0;
    integer noise_seed      = 32'h1234_5678;

    // Scenario controls
    integer scn_noise_amp   = 0;
    logic   scn_pm_enabled  = 1'b1;
    logic   scn_pm_invert   = 1'b0;
    logic   scn_carrier_on  = 1'b1; // 0 -> pure noise, no carrier at all

    // Reference telegram: ref_* is the time the telegram being sent right
    // now announces (the minute mark that ends it, per DCF77); cur_* is
    // the time of the minute mark that started the current minute, i.e.
    // what a decoder publishing during this minute must report.
    logic [5:0] ref_minute; logic [4:0] ref_hour; logic [5:0] ref_day;
    logic [2:0] ref_weekday; logic [3:0] ref_month; logic [7:0] ref_year;
    logic ref_cest, ref_dst_announce, ref_leap_announce;
    logic [5:0] cur_minute; logic [4:0] cur_hour; logic [5:0] cur_day;
    logic [2:0] cur_weekday; logic [3:0] cur_month; logic [7:0] cur_year;
    logic cur_cest;
    logic tg_bits [0:59];

    // cos(2*pi*n/12 + phi) for phi in {0, +PM_DEVIATION, -PM_DEVIATION},
    // tabulated once: evaluating $cos per sample dominated run time.
    real cos_tab [0:2][0:11];
    integer tab_i;
    initial begin
        for (tab_i = 0; tab_i < 12; tab_i = tab_i + 1) begin
            cos_tab[0][tab_i] = $cos(2.0 * PI * real'(tab_i) / 12.0);
            cos_tab[1][tab_i] = $cos(2.0 * PI * real'(tab_i) / 12.0 + PM_DEVIATION);
            cos_tab[2][tab_i] = $cos(2.0 * PI * real'(tab_i) / 12.0 - PM_DEVIATION);
        end
    end

    function automatic logic [8:0] next_ref_lfsr(input logic [8:0] l);
        logic [8:0] shifted;
        begin
            shifted = {1'b0, l[8:1]};
            if (l[0] || (shifted == 9'b0))
                shifted = shifted ^ 9'h110;
            next_ref_lfsr = shifted;
        end
    endfunction

    task automatic encode_telegram;
        integer i;
        logic [3:0] minute_units; logic [2:0] minute_tens;
        logic [3:0] hour_units; logic [1:0] hour_tens;
        logic [3:0] day_units; logic [1:0] day_tens;
        logic [3:0] month_units; logic month_tens;
        logic [3:0] year_units; logic [3:0] year_tens;
        begin
            for (i = 0; i < 60; i = i + 1) tg_bits[i] = 1'b0;
            tg_bits[16] = ref_dst_announce;
            tg_bits[17] = ref_cest;
            tg_bits[18] = !ref_cest;
            tg_bits[19] = ref_leap_announce;
            tg_bits[20] = 1'b1;

            // Each BCD digit is split explicitly (div/mod, then a plain
            // per-bit select) rather than through a concatenation whose
            // operand widths would silently mismatch the target.
            minute_units = 4'(ref_minute % 10); minute_tens = 3'(ref_minute / 10);
            tg_bits[21] = minute_units[0]; tg_bits[22] = minute_units[1];
            tg_bits[23] = minute_units[2]; tg_bits[24] = minute_units[3];
            tg_bits[25] = minute_tens[0]; tg_bits[26] = minute_tens[1];
            tg_bits[27] = minute_tens[2];
            tg_bits[28] = ^{tg_bits[21], tg_bits[22], tg_bits[23], tg_bits[24],
                             tg_bits[25], tg_bits[26], tg_bits[27]};

            hour_units = 4'(ref_hour % 10); hour_tens = 2'(ref_hour / 10);
            tg_bits[29] = hour_units[0]; tg_bits[30] = hour_units[1];
            tg_bits[31] = hour_units[2]; tg_bits[32] = hour_units[3];
            tg_bits[33] = hour_tens[0]; tg_bits[34] = hour_tens[1];
            tg_bits[35] = ^{tg_bits[29], tg_bits[30], tg_bits[31],
                             tg_bits[32], tg_bits[33], tg_bits[34]};

            day_units = 4'(ref_day % 10); day_tens = 2'(ref_day / 10);
            tg_bits[36] = day_units[0]; tg_bits[37] = day_units[1];
            tg_bits[38] = day_units[2]; tg_bits[39] = day_units[3];
            tg_bits[40] = day_tens[0]; tg_bits[41] = day_tens[1];
            tg_bits[42] = ref_weekday[0]; tg_bits[43] = ref_weekday[1];
            tg_bits[44] = ref_weekday[2];
            month_units = 4'(ref_month % 10); month_tens = 1'(ref_month / 10);
            tg_bits[45] = month_units[0]; tg_bits[46] = month_units[1];
            tg_bits[47] = month_units[2]; tg_bits[48] = month_units[3];
            tg_bits[49] = month_tens;
            year_units = 4'(ref_year % 10); year_tens = 4'(ref_year / 10);
            tg_bits[50] = year_units[0]; tg_bits[51] = year_units[1];
            tg_bits[52] = year_units[2]; tg_bits[53] = year_units[3];
            tg_bits[54] = year_tens[0]; tg_bits[55] = year_tens[1];
            tg_bits[56] = year_tens[2]; tg_bits[57] = year_tens[3];

            tg_bits[58] = ^{tg_bits[36], tg_bits[37], tg_bits[38], tg_bits[39],
                             tg_bits[40], tg_bits[41], tg_bits[42], tg_bits[43],
                             tg_bits[44], tg_bits[45], tg_bits[46], tg_bits[47],
                             tg_bits[48], tg_bits[49], tg_bits[50], tg_bits[51],
                             tg_bits[52], tg_bits[53], tg_bits[54], tg_bits[55],
                             tg_bits[56], tg_bits[57]};
        end
    endtask

    task automatic advance_reference_minute;
        begin
            cur_minute = ref_minute; cur_hour = ref_hour; cur_day = ref_day;
            cur_weekday = ref_weekday; cur_month = ref_month; cur_year = ref_year;
            cur_cest = ref_cest;
            if (ref_minute == 59) begin
                ref_minute = 0;
                if (ref_hour == 23) begin
                    ref_hour = 0;
                    if (ref_day == month_length(ref_year, ref_month)) begin
                        ref_day = 1;
                        if (ref_month == 12) begin
                            ref_month = 1; ref_year = ref_year + 1'b1;
                        end else ref_month = ref_month + 1'b1;
                    end else ref_day = ref_day + 1'b1;
                    ref_weekday = (ref_weekday == 7) ? 1 : ref_weekday + 1'b1;
                end else ref_hour = ref_hour + 1'b1;
            end else ref_minute = ref_minute + 1'b1;
            minutes_sent = minutes_sent + 1;
            encode_telegram();
            $display("  [min %0d] sync=%0d lock=%0d pm_min_locked=%0b freq_locked=%0b ml_q=%0b sec#=%0d decoded=%02d:%02d",
                     minutes_sent, dut.sync_state, lock_state, dut.detector_minute_locked,
                     dut.discipline_locked, dut.ml_qualified_q, second_number,
                     decoded_hour, decoded_minute);
        end
    endtask

    task automatic set_reference_time(
        input logic [5:0] minute, input logic [4:0] hour, input logic [5:0] day,
        input logic [2:0] weekday, input logic [3:0] month, input logic [7:0] year,
        input logic cest
    );
        begin
            ref_minute = minute; ref_hour = hour; ref_day = day;
            ref_weekday = weekday; ref_month = month; ref_year = year;
            ref_cest = cest; ref_dst_announce = 1'b0; ref_leap_announce = 1'b0;
            encode_telegram();
        end
    endtask

    // PM polarity of the current second: the fixed minute-marker pattern
    // (ten ones, five zeros) in seconds 0..14, the telegram bit elsewhere.
    function automatic logic pm_polarity(input integer sec);
        if (sec < 10) pm_polarity = 1'b1;
        else if (sec < 15) pm_polarity = 1'b0;
        else pm_polarity = tg_bits[sec];
    endfunction

    // One call per sample: returns the sample for "now" and advances every
    // piece of generator state by exactly one sample.
    task automatic next_sample(output logic signed [13:0] samp);
        real amp, val;
        integer phi_sel;
        integer noise_term;
        integer new_chip;
        begin
            if (!scn_carrier_on) begin
                noise_seed = noise_seed + 1;
                samp = 14'($random(noise_seed) % (scn_noise_amp > 0 ? scn_noise_amp : 4000));
            end else begin
                if (scn_pm_enabled && carrier_cycle >= PRN_START_CYCLE &&
                    carrier_cycle < PRN_START_CYCLE + CHIP_COUNT * CYCLES_PER_CHIP) begin
                    new_chip = (carrier_cycle - PRN_START_CYCLE) / CYCLES_PER_CHIP;
                    if (chip_index == -1) chip_index = 0;
                    else if (new_chip != chip_index) begin
                        ref_lfsr = next_ref_lfsr(ref_lfsr);
                        chip_index = new_chip;
                    end
                    phi_sel = (ref_lfsr[0] ^ scn_pm_invert ^ pm_polarity(second_in_min)) ? 1 : 2;
                end else begin
                    chip_index = -1;
                    ref_lfsr = 9'b0;
                    phi_sel = 0;
                end

                if (carrier_cycle < AM_WINDOW)
                    amp = REDUCED_AMPLITUDE;
                else if (carrier_cycle < 2 * AM_WINDOW)
                    amp = tg_bits[second_in_min] ? REDUCED_AMPLITUDE : FULL_AMPLITUDE;
                else
                    amp = FULL_AMPLITUDE;
                // Second 59 carries no AM mark at all (the minute gap).
                if (second_in_min == 59) amp = FULL_AMPLITUDE;

                val = amp * cos_tab[phi_sel][sample_in_cycle];
                if (scn_noise_amp > 0) begin
                    noise_seed = noise_seed + 1;
                    noise_term = ($random(noise_seed) % (2 * scn_noise_amp + 1));
                    val = val + real'(noise_term);
                end
                if (val > 8000.0) val = 8000.0;
                if (val < -8000.0) val = -8000.0;
                samp = 14'($rtoi(val));
            end

            sample_in_cycle = sample_in_cycle + 1;
            if (sample_in_cycle == 12) begin
                sample_in_cycle = 0;
                carrier_cycle = carrier_cycle + 1;
                if (carrier_cycle == SECOND_CYCLES) begin
                    carrier_cycle = 0;
                    second_in_min = second_in_min + 1;
                    if (second_in_min == 60) begin
                        second_in_min = 0;
                        advance_reference_minute();
                    end
                end
            end
        end
    endtask

    logic signed [13:0] next_val;
    logic generator_on = 1'b0;
    always @(posedge clk) begin
        if (generator_on) begin
            next_sample(next_val);
            sample <= next_val;
            sample_ce <= 1'b1;
        end else begin
            sample_ce <= 1'b0;
        end
    end

    // --- Scenario driver ---------------------------------------------------
    task automatic start_scenario;
        begin
            generator_on = 1'b0;
            rst <= 1'b1;
            repeat (4) @(posedge clk);
            sample_in_cycle = 0; carrier_cycle = 0; second_in_min = 0;
            chip_index = -1; ref_lfsr = 9'b0; minutes_sent = 0;
            telemetry_seen <= 1'b0; pps_seen <= 1'b0;
            rst <= 1'b0;
            @(posedge clk);
            generator_on = 1'b1;
        end
    endtask

    // Runs until time_valid asserts or max_minutes of transmitted minutes
    // elapse, whichever first.
    task automatic run_until_locked(input integer max_minutes, output logic locked);
        begin
            locked = 1'b0;
            while (!locked && minutes_sent < max_minutes) begin
                @(posedge clk);
                if (time_valid) locked = 1'b1;
            end
            // Let the PPS/UART path react to the lock before checking them.
            if (locked) repeat (2 * SECOND_CYCLES * 12) @(posedge clk);
        end
    endtask

    function automatic logic decoded_matches_current;
        decoded_matches_current =
            decoded_minute == cur_minute && decoded_hour == cur_hour &&
            decoded_day == cur_day && decoded_weekday == cur_weekday &&
            decoded_month == cur_month && decoded_year == cur_year &&
            decoded_cest == cur_cest;
    endfunction

    task automatic report_decoded(input string name);
        $display("  %s: decoded %02d:%02d %02d/%02d/%02d wd=%0d cest=%0b (expected %02d:%02d %02d/%02d/%02d wd=%0d cest=%0b) after %0d min",
                 name, decoded_hour, decoded_minute, decoded_day, decoded_month,
                 decoded_year, decoded_weekday, decoded_cest,
                 cur_hour, cur_minute, cur_day, cur_month, cur_year, cur_weekday,
                 cur_cest, minutes_sent);
    endtask

    logic run_locked;
    integer scenario_failures = 0;
    integer only_scenario = 0;

    task automatic expect_lock(input string name);
        begin
            run_until_locked(8, run_locked);
            report_decoded(name);
            if (!run_locked) begin
                $display("FAIL %s: never reached time_valid", name);
                scenario_failures = scenario_failures + 1;
            end else if (!decoded_matches_current()) begin
                $display("FAIL %s: decoded time does not match the transmitted telegram", name);
                scenario_failures = scenario_failures + 1;
            end else if (!pps_seen) begin
                $display("FAIL %s: PPS never pulsed after lock", name);
                scenario_failures = scenario_failures + 1;
            end else if (!telemetry_seen) begin
                $display("FAIL %s: UART telemetry never ran", name);
                scenario_failures = scenario_failures + 1;
            end else begin
                $display("PASS %s", name);
            end
        end
    endtask

    task automatic expect_no_lock(input string name, input integer minutes);
        begin
            run_until_locked(minutes, run_locked);
            if (run_locked) begin
                $display("FAIL %s: reached time_valid (decoded %02d:%02d)", name,
                         decoded_hour, decoded_minute);
                scenario_failures = scenario_failures + 1;
            end else if (pps_seen) begin
                $display("FAIL %s: PPS pulsed without a qualified time", name);
                scenario_failures = scenario_failures + 1;
            end else begin
                $display("PASS %s: no qualified time published in %0d min", name, minutes);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("scenario=%d", only_scenario)) only_scenario = 0;

        // 1. Clean signal: lock, correct time, PPS and UART.
        if (only_scenario == 0 || only_scenario == 1) begin
            start_scenario();
            set_reference_time(6'd15, 5'd10, 6'd21, 3'd3, 4'd6, 8'd24, 1'b1);
            scn_noise_amp = 0; scn_pm_enabled = 1'b1; scn_pm_invert = 1'b0;
            scn_carrier_on = 1'b1;
            expect_lock("clean_signal");
        end

        // 2. Noise only: never publishes.
        if (only_scenario == 0 || only_scenario == 2) begin
            start_scenario();
            set_reference_time(6'd0, 5'd0, 6'd1, 3'd1, 4'd1, 8'd24, 1'b0);
            scn_carrier_on = 1'b0; scn_noise_amp = 3000;
            expect_no_lock("noise_only", 5);
        end

        // 3. AM only (no PM burst): no minute marker, so no qualified lock.
        if (only_scenario == 0 || only_scenario == 3) begin
            start_scenario();
            set_reference_time(6'd0, 5'd8, 6'd10, 3'd1, 4'd3, 8'd25, 1'b0);
            scn_carrier_on = 1'b1; scn_noise_amp = 0; scn_pm_enabled = 1'b0;
            expect_no_lock("am_only_no_pm", 5);
            scn_pm_enabled = 1'b1;
        end

        // 4. PM polarity inverted: still locks and decodes.
        if (only_scenario == 0 || only_scenario == 4) begin
            start_scenario();
            set_reference_time(6'd45, 5'd23, 6'd28, 3'd2, 4'd2, 8'd23, 1'b0);
            scn_carrier_on = 1'b1; scn_noise_amp = 0; scn_pm_invert = 1'b1;
            expect_lock("pm_polarity_inverted");
            scn_pm_invert = 1'b0;
        end

        // 5. Noisy but real signal.
        if (only_scenario == 0 || only_scenario == 5) begin
            start_scenario();
            set_reference_time(6'd30, 5'd12, 6'd5, 3'd5, 4'd9, 8'd24, 1'b0);
            scn_carrier_on = 1'b1; scn_noise_amp = 900;
            expect_lock("noisy_signal");
            scn_noise_amp = 0;
        end

        // 6. Midnight / month-end rollover inside the observation window.
        if (only_scenario == 0 || only_scenario == 6) begin
            start_scenario();
            set_reference_time(6'd58, 5'd23, 6'd30, 3'd2, 4'd4, 8'd24, 1'b1);
            scn_carrier_on = 1'b1; scn_noise_amp = 0;
            expect_lock("midnight_month_end");
        end

        if (scenario_failures != 0) begin
            $display("dcf77_system_tb: FAIL (%0d scenario(s) failed)", scenario_failures);
            $fatal(1, "system test failures");
        end
        $display("dcf77_system_tb: PASS");
        $finish;
    end

    initial begin
        #10_000_000_000;
        $fatal(1, "dcf77_system_tb: timeout");
    end
endmodule
