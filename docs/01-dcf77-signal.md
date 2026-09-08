# DCF77 signal used by this receiver

## Carrier and modulation

DCF77 transmits on a **77.5 kHz** long-wave carrier. Each second carries both an amplitude-modulated (AM) symbol and a phase-modulated (PM) symbol. The two channels are deliberately useful in different parts of the second and can be processed separately.

For the AM channel, the carrier is reduced to roughly **15%** of nominal amplitude at the beginning of each second. A reduction lasting about **100 ms** represents AM bit 0; about **200 ms** represents AM bit 1. Second 59 is the minute marker and has no normal AM reduction.

The PM channel uses small phase excursions of approximately **±13°** driven by a **512-bit pseudo-random phase pattern**. PM bit 1 is the inverted/sign-reversed version of the PM bit-0 pattern. In Engeler's detector the useful PM region is taken after the AM transient, roughly from **0.2 s to 1 s**.

The paper also models a short **250 µs transmitter blanking interval**. Any reproduction aiming at the reported timing performance should allow for that transient rather than modelling the AM edge as ideal.

## Orthogonality exploited by the receiver

The implementation separates AM and PM because they are orthogonal in two practical senses:

1. AM information is contained in envelope magnitude; PM information is contained in carrier phase.
2. AM is useful mainly during the first 0.2 s; PM is used over the remainder of the second.

That separation is the reason the demonstration design uses different effective bandwidths for the AM and PM detector paths.

## DCF77 minute frame

The following table reconstructs the frame information shown in the paper. The weights are BCD weights.

| Second | Meaning |
|---:|---|
| 0 | fixed AM 0; PM is part of the known minute-start pattern |
| 1-14 | AM carries weather/alarm service data; PM remains part of the known minute-start pattern |
| 15 | call/antenna indication |
| 16 | A1: announcement of CET/CEST change |
| 17 | Z1: time-zone bit, 0 = CET, 1 = CEST |
| 18 | Z2, complement of Z1 |
| 19 | A2: leap-second announcement |
| 20 | start-of-time-code marker, fixed 1 |
| 21 | minute weight 1 |
| 22 | minute weight 2 |
| 23 | minute weight 4 |
| 24 | minute weight 8 |
| 25 | minute weight 10 |
| 26 | minute weight 20 |
| 27 | minute weight 40 |
| 28 | P1: parity over minute bits 21-27 |
| 29 | hour weight 1 |
| 30 | hour weight 2 |
| 31 | hour weight 4 |
| 32 | hour weight 8 |
| 33 | hour weight 10 |
| 34 | hour weight 20 |
| 35 | P2: parity over hour bits 29-34 |
| 36 | day-of-month weight 1 |
| 37 | day-of-month weight 2 |
| 38 | day-of-month weight 4 |
| 39 | day-of-month weight 8 |
| 40 | day-of-month weight 10 |
| 41 | day-of-month weight 20 |
| 42 | weekday weight 1 |
| 43 | weekday weight 2 |
| 44 | weekday weight 4 |
| 45 | month weight 1 |
| 46 | month weight 2 |
| 47 | month weight 4 |
| 48 | month weight 8 |
| 49 | month weight 10 |
| 50 | year weight 1 |
| 51 | year weight 2 |
| 52 | year weight 4 |
| 53 | year weight 8 |
| 54 | year weight 10 |
| 55 | year weight 20 |
| 56 | year weight 40 |
| 57 | year weight 80 |
| 58 | P3: parity over date bits 36-57 |
| 59 | minute marker: no normal AM pulse; PM special value |

For the PM channel, the paper shows a known pattern in the first 15 seconds: PM bits 0-9 are 1 and bits 10-14 are 0. This pattern is valuable for minute/second synchronisation. After that, the PM data largely follows the time-code information.

## Symbols used in the detector

The paper defines two derived AM templates:

- `AM_1/2 = (AM0 + AM1) / 2`: average AM envelope, used for second synchronisation.
- `AM_delta = AM1 - AM0`: difference template, used to decide AM bit 0 versus bit 1.

The exact waveform of these templates should be passed through, or otherwise adapted to, the actual analog input response. A high-Q ferrite antenna and narrow band-pass distort the ideal square envelope and therefore alter the optimum correlation template.

## Practical implication for this repository

The AM decoder is useful for initial bring-up because it is easy to observe. The PM path is the route to the paper's best sensitivity and timing precision. A successful recreation should therefore expose both envelope and phase observables during development, rather than hiding them behind a final 1-bit/s interface.
