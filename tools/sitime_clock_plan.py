#!/usr/bin/env python3
"""Check the preferred SiTime/ECP5 integer clock plan for the DCF77 rebuild."""

from fractions import Fraction

DCF77_CARRIER_HZ = 77_500
ADC_RATE_HZ = 930_000
TCXO_HZ = 24_180_000
PLL_MULT = 5
SYSTEM_HZ = TCXO_HZ * PLL_MULT


def require_integer_ratio(numerator: int, denominator: int, label: str) -> int:
    ratio = Fraction(numerator, denominator)
    if ratio.denominator != 1:
        raise AssertionError(f"{label} is not integer: {ratio}")
    return ratio.numerator


def main() -> None:
    samples_per_carrier = require_integer_ratio(
        ADC_RATE_HZ, DCF77_CARRIER_HZ, "ADC/carrier"
    )
    tcxo_clocks_per_sample = require_integer_ratio(
        TCXO_HZ, ADC_RATE_HZ, "TCXO/ADC"
    )
    tcxo_clocks_per_carrier = require_integer_ratio(
        TCXO_HZ, DCF77_CARRIER_HZ, "TCXO/carrier"
    )
    sys_clocks_per_sample = require_integer_ratio(
        SYSTEM_HZ, ADC_RATE_HZ, "system/ADC"
    )
    sys_clocks_per_carrier = require_integer_ratio(
        SYSTEM_HZ, DCF77_CARRIER_HZ, "system/carrier"
    )

    prn_chip_samples = 120 * samples_per_carrier
    prn_chip_sys_clocks = 120 * sys_clocks_per_carrier
    prn_samples = 512 * prn_chip_samples
    prn_start_samples = ADC_RATE_HZ // 5  # 200 ms
    prn_end_samples = prn_start_samples + prn_samples

    print(f"DCF77 carrier            : {DCF77_CARRIER_HZ:,} Hz")
    print(f"ADC rate                 : {ADC_RATE_HZ:,} Hz")
    print(f"SiTime DCTCXO            : {TCXO_HZ:,} Hz")
    print(f"ECP5 system clock        : {SYSTEM_HZ:,} Hz")
    print()
    print(f"samples/carrier          : {samples_per_carrier}")
    print(f"TCXO clocks/sample       : {tcxo_clocks_per_sample}")
    print(f"TCXO clocks/carrier      : {tcxo_clocks_per_carrier}")
    print(f"system clocks/sample     : {sys_clocks_per_sample}")
    print(f"system clocks/carrier    : {sys_clocks_per_carrier}")
    print()
    print(f"samples/PRN chip         : {prn_chip_samples:,}")
    print(f"system clocks/PRN chip   : {prn_chip_sys_clocks:,}")
    print(f"PRN start sample         : {prn_start_samples:,}")
    print(f"PRN duration samples     : {prn_samples:,}")
    print(f"PRN end sample           : {prn_end_samples:,}")
    print(f"PRN end time             : {prn_end_samples / ADC_RATE_HZ:.9f} s")

    assert samples_per_carrier == 12
    assert tcxo_clocks_per_sample == 26
    assert tcxo_clocks_per_carrier == 312
    assert sys_clocks_per_sample == 130
    assert sys_clocks_per_carrier == 1560
    assert prn_chip_samples == 1440
    assert prn_start_samples == 186_000
    assert prn_samples == 737_280
    assert prn_end_samples == 923_280


if __name__ == "__main__":
    main()
