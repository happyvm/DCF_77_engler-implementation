#!/usr/bin/env python3
"""Clock-plan calculator for the ECP5 DCF77 rebuild.

This tool documents the numerical relationship between the fixed FPGA clock,
the fractional ADC sample scheduler, and DCF77 carrier/PRN timing.

It is intentionally dependency-free so the values in the design documentation
can be reproduced in CI or on a developer workstation.
"""

from __future__ import annotations

import argparse
import math

DCF77_CARRIER_HZ = 77_500.0
DEFAULT_SYSCLK_HZ = 125_000_000.0
DEFAULT_SAMPLE_HZ = 930_000.0
DEFAULT_PHASE_BITS = 40


def phase_increment(sysclk_hz: float, sample_hz: float, bits: int) -> int:
    return round((1 << bits) * sample_hz / sysclk_hz)


def realised_rate(sysclk_hz: float, increment: int, bits: int) -> float:
    return increment * sysclk_hz / (1 << bits)


def ppm_error(actual: float, target: float) -> float:
    return (actual / target - 1.0) * 1e6


def increment_lsb_ppm(sysclk_hz: float, sample_hz: float, bits: int) -> float:
    return (sysclk_hz / (1 << bits)) / sample_hz * 1e6


def quantisation_jitter_rms(sysclk_hz: float) -> float:
    # Uniform timing quantisation across one system-clock interval.
    return (1.0 / sysclk_hz) / math.sqrt(12.0)


def jitter_snr_db(input_hz: float, sigma_seconds: float) -> float:
    return -20.0 * math.log10(2.0 * math.pi * input_hz * sigma_seconds)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sysclk", type=float, default=DEFAULT_SYSCLK_HZ)
    parser.add_argument("--sample-rate", type=float, default=DEFAULT_SAMPLE_HZ)
    parser.add_argument("--phase-bits", type=int, default=DEFAULT_PHASE_BITS)
    parser.add_argument(
        "--trim-ppm",
        type=float,
        default=0.0,
        help="requested scheduler correction in ppm",
    )
    args = parser.parse_args()

    inc = phase_increment(args.sysclk, args.sample_rate, args.phase_bits)
    one_ppm_counts = inc / 1e6
    trim_counts = round(one_ppm_counts * args.trim_ppm)
    corrected_inc = inc + trim_counts

    nominal_actual = realised_rate(args.sysclk, inc, args.phase_bits)
    corrected_actual = realised_rate(args.sysclk, corrected_inc, args.phase_bits)

    tclk = 1.0 / args.sysclk
    sigma = quantisation_jitter_rms(args.sysclk)
    max_carrier_phase_deg = 360.0 * DCF77_CARRIER_HZ * tclk

    print(f"system clock               : {args.sysclk:.6f} Hz")
    print(f"target sample rate         : {args.sample_rate:.6f} Hz")
    print(f"phase accumulator width    : {args.phase_bits} bits")
    print(f"nominal phase increment    : {inc}")
    print(f"realised nominal rate      : {nominal_actual:.12f} Hz")
    print(f"nominal numerical error    : {ppm_error(nominal_actual, args.sample_rate):.9f} ppm")
    print(f"increment resolution       : {increment_lsb_ppm(args.sysclk, args.sample_rate, args.phase_bits):.9f} ppm/LSB")
    print(f"counts per 1 ppm           : {one_ppm_counts:.6f}")
    print(f"requested trim             : {args.trim_ppm:.6f} ppm")
    print(f"trim increment counts      : {trim_counts}")
    print(f"corrected phase increment  : {corrected_inc}")
    print(f"corrected sample rate      : {corrected_actual:.9f} Hz")
    print(f"system clock period        : {tclk * 1e9:.6f} ns")
    print(f"quantisation RMS estimate  : {sigma * 1e9:.6f} ns")
    print(f"77.5 kHz jitter SNR est.   : {jitter_snr_db(DCF77_CARRIER_HZ, sigma):.3f} dB")
    print(f"one-clock carrier phase    : {max_carrier_phase_deg:.6f} deg")
    print()
    print("DCF77 sample-domain invariants")
    print(f"samples / carrier cycle    : {args.sample_rate / DCF77_CARRIER_HZ:.9f}")
    print(f"samples / PRN chip         : {args.sample_rate / (DCF77_CARRIER_HZ / 120.0):.9f}")
    print(f"samples at +200 ms         : {args.sample_rate * 0.2:.3f}")
    print(f"samples in 512 PRN chips   : {512 * 1440}")
    print(f"PRN end sample position    : {186000 + 512 * 1440}")


if __name__ == "__main__":
    main()
