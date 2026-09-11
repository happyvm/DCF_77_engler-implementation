"""Tests for the BEA-37 timing-characterisation parsing/generation scripts.

These use committed fixtures (not live tool output) so a silent change in the
nextpnr report/log format — or in the port parser — is caught here instead of
producing silently wrong numbers in reports/timing/*.csv.
"""

import json
import unittest
from pathlib import Path

from tools.timing import nextpnr as np
from tools.timing import report as reportmod
from tools.timing import svparse
from tools.timing import wrapper as wrappergen

FIXTURES = Path(__file__).resolve().parent / "fixtures"


class NextpnrReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.report_json = (FIXTURES / "nextpnr_report_fixture.json").read_text()
        self.log_text = (FIXTURES / "nextpnr_log_fixture.txt").read_text()

    def test_parse_report_fields(self) -> None:
        res = np.parse_report(self.report_json)
        self.assertAlmostEqual(res.fmax_mhz, 250.0, places=3)
        self.assertAlmostEqual(res.constraint_mhz, 125.0, places=3)
        self.assertAlmostEqual(res.worst_slack_ns, 8.0 - 1000.0 / 250.0, places=3)
        self.assertEqual(res.lut4, 1234)
        self.assertEqual(res.ff, 567)
        self.assertEqual(res.ebr18, 2)
        self.assertEqual(res.mult18x18d, 3)
        self.assertEqual(res.pll, 0)

    def test_parse_critical_path(self) -> None:
        res = np.parse_report(self.report_json)
        self.assertEqual(len(res.critical_paths), 1)
        cp = res.critical_paths[0]
        self.assertEqual(cp.source, "top.a_q")
        self.assertEqual(cp.dest, "top.b_q")
        self.assertEqual(cp.segments, 4)
        self.assertAlmostEqual(cp.logic_ns, 0.25, places=3)
        self.assertAlmostEqual(cp.route_ns, 3.0, places=3)
        self.assertAlmostEqual(cp.total_ns, 3.25, places=3)

    def test_parse_log(self) -> None:
        parsed = np.parse_log(self.log_text)
        self.assertIn("$glbnet$clk", parsed["fmax"])
        self.assertAlmostEqual(parsed["fmax"]["$glbnet$clk"]["achieved"], 250.0)
        self.assertEqual(parsed["utilization"]["TRELLIS_COMB"], 1234)
        self.assertEqual(parsed["utilization"]["MULT18X18D"], 3)

    def test_cross_check_consistent(self) -> None:
        res = np.parse_report(self.report_json)
        parsed = np.parse_log(self.log_text)
        self.assertEqual(np.cross_check(res, parsed), [])

    def test_cross_check_detects_mismatch(self) -> None:
        res = np.parse_report(self.report_json)
        parsed = np.parse_log(self.log_text)
        parsed["fmax"]["$glbnet$clk"]["achieved"] = 99.0
        problems = np.cross_check(res, parsed)
        self.assertTrue(any("fmax mismatch" in p for p in problems))

    def test_missing_fmax_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            np.parse_report(json.dumps({"utilization": {}}))


class PortParserTest(unittest.TestCase):
    SRC = """
    module demo #(
        parameter int W = 8,
        parameter int OUTW = 2*W + 1
    ) (
        input  logic clk,
        input  logic rst_n,
        input  logic signed [W-1:0] data,
        input  logic signed [OUTW-1:0] gain,
        output logic signed [OUTW-1:0] result,
        output logic valid
    );
    endmodule
    """

    def test_ports(self) -> None:
        ports = svparse.parse_module_ports(self.SRC, "demo")
        names = [p.name for p in ports]
        self.assertEqual(names, ["clk", "rst_n", "data", "gain", "result", "valid"])
        by = {p.name: p for p in ports}
        self.assertEqual(by["data"].direction, "input")
        self.assertEqual(by["data"].dim, "[W-1:0]")
        self.assertEqual(by["result"].dim, "[OUTW-1:0]")
        self.assertEqual(by["valid"].dim, "")

    def test_parameter_text(self) -> None:
        text = svparse.get_parameter_text(self.SRC, "demo")
        self.assertIn("parameter int W = 8", text)
        self.assertIn("parameter int OUTW = 2*W + 1", text)

    def test_comments_are_stripped(self) -> None:
        src = "module m ( /* c, c */ input logic a, // trailing\n output logic b ); endmodule"
        ports = svparse.parse_module_ports(src, "m")
        self.assertEqual([p.name for p in ports], ["a", "b"])

    def test_ifdef_formal_ports_are_dropped(self) -> None:
        src = (
            "module m (\n"
            "  input logic clk,\n"
            "  output logic y\n"
            "`ifdef FORMAL\n"
            "  , output logic dbg\n"
            "`endif\n"
            "); endmodule\n"
        )
        names = [p.name for p in svparse.parse_module_ports(src, "m")]
        self.assertEqual(names, ["clk", "y"])
        self.assertNotIn("dbg", names)

    def test_ifndef_block_is_kept_when_undefined(self) -> None:
        src = (
            "module m (\n"
            "`ifndef FORMAL\n"
            "  input logic a,\n"
            "`endif\n"
            "  output logic b\n"
            "); endmodule\n"
        )
        names = [p.name for p in svparse.parse_module_ports(src, "m")]
        self.assertEqual(names, ["a", "b"])


class WrapperTest(unittest.TestCase):
    SRC = """
    module blk #(parameter int W = 4) (
        input  logic clk,
        input  logic rst,
        input  logic signed [W-1:0] x,
        output logic signed [W:0] y,
        output logic done
    );
    endmodule
    """

    def test_wrapper_structure(self) -> None:
        w, ports = wrappergen.wrapper_for_source("blk", self.SRC, "clk", "blk.sv")
        # DUT parameter block is re-emitted so dimensions resolve.
        self.assertIn("module blk__timing #(", w)
        self.assertIn("parameter int W = 4", w)
        # registered inputs
        self.assertIn("always_ff @(posedge clk) sig_x <= sig_x + 1'b1;", w)
        # reset held inactive
        self.assertIn("assign sig_rst = 1'b0;", w)
        # clock routed, not counted
        self.assertIn("assign sig_clk = clk;", w)
        self.assertNotIn("sig_clk <= sig_clk", w)
        # outputs registered then folded into a pad-free signature
        self.assertIn("output logic [15:0] sig_o", w)
        self.assertIn("always_ff @(posedge clk) sig_y_q <= sig_y_w;", w)
        self.assertIn("assign sig_fold = ^{sig_y_q, sig_done_q}", w)
        self.assertIn("assign sig_o = sig_q ^ sig_ctr;", w)
        # no per-port pads: the only outputs are clk and sig_o
        self.assertNotIn("_o,", w.split(");", 1)[0])
        # reset_cycle-style functional input must NOT be treated as reset
        self.assertNotIn("reset_cycle", w)

    def test_combinational_module_has_no_clock(self) -> None:
        src = "module c (input logic [3:0] a, output logic [3:0] b); endmodule"
        w, _ = wrappergen.wrapper_for_source("c", src, "clk", "c.sv")
        self.assertIn("module c__timing", w)
        self.assertNotIn("sig_clk", w)
        self.assertIn("output logic [15:0] sig_o", w)

    def test_param_override_in_instance(self) -> None:
        w, _ = wrappergen.wrapper_for_source(
            "blk", self.SRC, "clk", "blk.sv", {"QUALIFICATION_ENABLED": "1'b1"})
        self.assertIn("blk #(.QUALIFICATION_ENABLED(1'b1)) dut (", w)


class ClassifyTest(unittest.TestCase):
    def test_bands(self) -> None:
        self.assertIn("excellent", reportmod.classify(250.0, "single-cycle"))
        self.assertIn("very-good", reportmod.classify(180.0, "single-cycle"))
        self.assertIn("acceptable", reportmod.classify(160.0, "single-cycle"))
        self.assertIn("weak", reportmod.classify(130.0, "single-cycle"))
        self.assertIn("failing", reportmod.classify(100.0, "single-cycle"))

    def test_multicycle_is_annotated(self) -> None:
        self.assertIn("multicycle", reportmod.classify(100.0, "multicycle"))
        self.assertIn("multicycle", reportmod.classify(100.0, "low-rate-control"))


if __name__ == "__main__":
    unittest.main()
