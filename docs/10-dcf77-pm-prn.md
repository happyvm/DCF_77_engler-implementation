# DCF77 pseudo-random phase modulation (PRN/PZF)

This document closes one of the main implementation gaps left by the Engeler paper: the exact structure needed to generate the DCF77 pseudo-random phase sequence used by the PM detector.

## Status

**Resolved from PTB sources.** The receiver does not need to guess or learn the sequence from the air.

The authoritative implementation description is given by PTB publications by Peter Hetzel and by Piester/Hetzel/Bauch. The 2004 PTB description is consistent with the sequence generator shown in the 1988 EFTF paper.

## Generator structure

The transmitter uses a **9-stage feedback shift register**. PTB states that outputs/stages **5 and 9 are XORed and fed back to the register input**.

Equivalent characteristic polynomial, using the common polynomial convention, is:

```text
x^9 + x^5 + 1
```

A normal maximal-length 9-bit LFSR cannot start from the all-zero state, so the DCF77 generator includes an auxiliary flip-flop that forces the register out of zero at the start of each cycle. This produces the transmitted 512-chip balanced cycle.

An equivalent right-shifting Galois implementation uses mask:

```text
0x110
```

A small executable reference implementation is stored in [`../tools/dcf77_prn.py`](../tools/dcf77_prn.py).

The corresponding generator and soft correlator RTL are described in
[`32-pm-prn-rtl.md`](32-pm-prn-rtl.md).

## Known sequence prefix and invariants

The generated sequence begins with:

```text
00000100011000010011100101010110000...
```

The implementation in this repository verifies:

- exactly **512 chips** per cycle;
- exactly **256 zeroes and 256 ones**;
- the known sequence prefix above;
- PM data `1` is the exact inversion of PM data `0`.

These properties should also become HDL testbench assertions when the FPGA implementation is added.

## Exact chip timing

The PRN clock is derived directly from the DCF77 carrier:

```text
f_carrier = 77,500 Hz
f_chip    = 77,500 / 120 = 645.833333... Hz
T_chip    = 120 / 77,500 = 1.548387096... ms
```

One complete 512-chip cycle therefore lasts:

```text
512 * 120 / 77,500 = 792.7741935 ms
```

The PRN cycle starts **200 ms after the beginning of the second**. Therefore the last chip ends at:

```text
200.000 ms + 792.774 ms = 992.774 ms
```

The remaining unmodulated interval is:

```text
7.225806 ms = 560 carrier cycles
```

In carrier-cycle coordinates:

```text
second start            : cycle 0
PRN start               : cycle 15,500
PRN length              : 61,440 carrier cycles
PRN end                 : cycle 76,940
unmodulated tail         : 560 carrier cycles
next second              : cycle 77,500
```

This relation is particularly useful in this project because the Engeler ADC rate is exactly `12 * 77.5 kHz`: carrier, ADC and PRN timing can all be represented with integer counters in the nominal clock domain.

## Sequence inversion keying

DCF77 does not choose a different PRN code for binary zero and one. It uses **sequence inversion keying (SIK)**:

```text
data 0 -> transmit PRN unchanged
data 1 -> transmit bitwise-inverted PRN
```

The 1988 PTB transmitter description maps the two modulator logic states to the two carrier phase states around the mean phase. The later PTB description and the Engeler receiver use approximately **±13 degrees** as the phase excursion.

For receiver implementation, do not hard-code an absolute RF phase sign into the time decoder. Correlation polarity can be established during acquisition because analog stages, mixer sign and antenna orientation can introduce a 180-degree sign inversion. What matters is that the two data hypotheses are opposite PRN templates.

## PM minute marker and special seconds

The PM minute identification differs from the AM minute marker.

Normal operation:

| Second | PM meaning |
|---:|---|
| 0-9 | ten **inverted** PRN cycles, i.e. ten logical `1` symbols; this is the minute identifier |
| 10-14 | non-inverted / logical `0` PRN cycles; no ordinary time information is encoded here |
| 15 onward | PM binary information follows the DCF77 time information |
| 59 | unlike AM, PM does not omit the PRN cycle; it is a normal non-inverted/logical `0` cycle before the next minute identifier |

When a leap second is inserted, PTB states that the run of ten inverted PRN cycles used for minute identification appears **one second later**.

The FPGA minute synchroniser should therefore search for the known `1111111111` PM run rather than copying the AM rule “missing pulse at second 59”.

## Correlation bandwidth

PTB gives the PRN spectrum a sinc-like envelope. The first main-lobe nulls are at roughly:

```text
77.5 kHz ± 645.833 Hz
```

Therefore a receiver intended to preserve at least the main PRN lobe needs approximately:

```text
2 * 645.833 = 1.292 kHz
```

of RF/IF bandwidth around the carrier. This is an important lower bound for the **analog** front-end. The much narrower AM digital bandwidth must not be used as the analog filter specification.

Engeler deliberately uses a much wider PM digital path than the AM path and then obtains processing gain by correlation.

## HDL implementation recommendation

Implement the PRN generator as a deterministic block with these interfaces:

```text
reset_cycle
chip_enable
received_data_hypothesis
prn_chip
prn_chip_inverted
chip_index[8:0]
```

The block should reset once per hypothesised second and only advance on the `carrier/120` chip enable. During acquisition, generate several time-shifted hypotheses around the estimated 200 ms start and correlate them against received phase.

Do not regenerate chips from a free-running unrelated oscillator. Derive the chip-enable timing from the same disciplined clock domain used for carrier detection.

## Verification before RF testing

Before feeding real DCF77 samples into the detector:

1. run `python3 tools/dcf77_prn.py --verify`;
2. confirm the HDL produces the same first 512 bits;
3. confirm 256/256 balance;
4. correlate the sequence with itself and verify the main peak;
5. correlate against the inverted sequence and verify opposite sign;
6. offset by one chip and verify the expected correlation reduction;
7. simulate a full second with PRN starting at exactly 200 ms and ending 560 carrier cycles before the next second.

## Sources

- P. Hetzel, *Time dissemination via the LF transmitter DCF77 using a pseudo-random phase-shift keying of the carrier*, European Frequency and Time Forum, 1988.
- D. Piester, P. Hetzel, A. Bauch, *Zeit- und Normalfrequenzverbreitung mit DCF77*, PTB-Mitteilungen 114 (2004), section 4.3.
- Daniel Engeler, *Performance Analysis and Receiver Architectures of DCF77 Radio-Controlled Clocks*, IEEE TUFFC, 2012.

See [`references.md`](references.md) for source links.
