import unittest
from collections import Counter

from tools.check_resource_budget import cell_counts, usage_from_counts


class ResourceBudgetTest(unittest.TestCase):
    def test_counts_mapped_ecp5_cells(self) -> None:
        netlist = {
            "modules": {
                "top": {
                    "cells": {
                        "a": {"type": "LUT4"},
                        "b": {"type": "TRELLIS_FF"},
                        "c": {"type": "MULT18X18D"},
                    }
                },
                "child": {"cells": {"ram": {"type": "DP16KD"}}},
            }
        }
        counts = cell_counts(netlist)
        self.assertEqual(counts, Counter({
            "LUT4": 1, "TRELLIS_FF": 1, "MULT18X18D": 1, "DP16KD": 1
        }))
        self.assertEqual(usage_from_counts(counts), {
            "lut4_equivalent": 1,
            "flip_flops": 1,
            "ebr18_blocks": 1,
            "mult18x18": 1,
            "clock_managers": 0,
        })


if __name__ == "__main__":
    unittest.main()
