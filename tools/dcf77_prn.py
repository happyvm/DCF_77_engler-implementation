#!/usr/bin/env python3
"""Generate and verify the 512-chip DCF77 pseudo-random phase sequence.

The implementation follows the 9-stage generator described by PTB:
feedback taps 5 and 9, with an auxiliary start mechanism that escapes
the all-zero state. The equivalent Galois implementation uses mask 0x110.

Data bit 0 transmits the generated sequence unchanged.
Data bit 1 transmits the bitwise-inverted sequence.
"""

from __future__ import annotations

import argparse

CHIP_COUNT = 512
GALOIS_MASK = 0x110
KNOWN_PREFIX = "00000100011000010011100101010110000"


def prn_bits() -> list[int]:
    """Return one 512-chip DCF77 PRN cycle as 0/1 integers."""
    lfsr = 0
    out: list[int] = []

    for _ in range(CHIP_COUNT):
        chip = lfsr & 1
        out.append(chip)

        lfsr >>= 1
        # Equivalent to the PTB auxiliary FF forcing the register
        # out of the all-zero state, plus normal feedback.
        if chip or lfsr == 0:
            lfsr ^= GALOIS_MASK

    return out


def encoded_bits(data_bit: int) -> list[int]:
    """Return the chip sequence used to transmit one binary data bit."""
    if data_bit not in (0, 1):
        raise ValueError("data_bit must be 0 or 1")
    seq = prn_bits()
    return [chip ^ data_bit for chip in seq]


def verify() -> None:
    seq = prn_bits()
    text = "".join(str(bit) for bit in seq)

    assert len(seq) == 512
    assert sum(seq) == 256
    assert text.startswith(KNOWN_PREFIX)
    assert encoded_bits(1) == [bit ^ 1 for bit in seq]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--data-bit",
        type=int,
        choices=(0, 1),
        default=0,
        help="0: PRN unchanged, 1: PRN inverted",
    )
    parser.add_argument(
        "--format",
        choices=("bits", "hex"),
        default="bits",
        help="output representation",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="run built-in sequence invariants before output",
    )
    args = parser.parse_args()

    if args.verify:
        verify()

    seq = encoded_bits(args.data_bit)

    if args.format == "bits":
        print("".join(str(bit) for bit in seq))
    else:
        value = int("".join(str(bit) for bit in seq), 2)
        print(f"{value:0128x}")


if __name__ == "__main__":
    main()
