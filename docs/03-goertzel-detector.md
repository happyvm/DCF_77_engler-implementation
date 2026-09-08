# Goertzel detector and synchronisation

## Purpose

The Goertzel detector is the key digital detector implemented in Engeler's demonstration receiver. It estimates the complex carrier at 77.5 kHz and derives both amplitude and phase information while using only a small, fixed amount of state.

For a conventional N-point DFT bin,

```text
X(k) = sum(n=0..N-1) x(n) * exp(-j*2*pi*n*k/N)
```

Engeler starts from the efficient recursive Goertzel/IIR structure and periodically scales its two state variables. The scaling makes the recursive detector behave like an exponentially weighted moving average, thereby setting the effective frequency selectivity without an N-sample sliding window.

## Scaling and effective bandwidth

When the Goertzel state is scaled once per carrier cycle, the paper gives the approximate relationship

```text
B_3dB ~= 0.32 * (1 - k) * f_c
```

where `k` is the state-scaling factor and `f_c = 77.5 kHz`.

The implementation deliberately uses different selectivity for different observables:

| Path | Approx. 3 dB bandwidth |
|---|---:|
| AM | 15 Hz |
| PM | 930 Hz |
| Carrier reference | adaptive; narrowed as clock accuracy improves |

AM can be narrow because envelope information changes comparatively slowly. PM must be much wider to preserve the fast pseudo-random phase pattern and timing information.

## Three complex detector states

Maintain three Goertzel instances:

```text
X_carrier  -> long/narrow carrier reference
X_AM       -> AM-optimised bandwidth
X_PM       -> PM-optimised bandwidth
```

The carrier phase is

```text
phi_carrier = arg(X_carrier)
```

A CORDIC is a natural FPGA implementation for the vector angle/rotation operations.

### AM observable

The most direct AM estimate is

```text
A_AM = |X_AM|
```

If the signal is first rotated by `-phi_carrier`, the useful envelope can instead be taken approximately from the real component, avoiding a full magnitude operation in the main data path.

### PM observable

The paper expresses PM phase relative to the carrier as the argument of the PM component relative to the carrier reference. Because the DCF77 phase deviation is only about ±13°, after rotation into the carrier frame the PM evidence can be approximated by the imaginary component. This is attractive for fixed-point hardware.

## Second synchronisation

A receiver must establish, in order:

1. carrier frequency/phase reference;
2. second boundary;
3. minute boundary/time-code position.

### AM-based second sync

A robust AM method correlates the received envelope with the average symbol template

```text
AM_1/2 = (AM0 + AM1) / 2
```

The correlation peak is roughly **400 ms wide**. Repeated seconds add coherently, allowing long averaging against noise. The paper finds AM synchronisation more robust than PM synchronisation in AWGN, so AM can give the coarse position used to constrain the PM search.

A much simpler alternative is a threshold on the AM falling edge. It can be precise with a wide analog bandwidth, but becomes more susceptible to noise and is not the main high-immunity method.

### PM-based second sync

Correlate the demodulated PM phase with the known **PM0 512-bit pseudo-random pattern**. The correlation can locate the second to about one carrier cycle, approximately **13 µs**, in the ideal case.

A complication is polarity: PM0 and PM1 produce correlation peaks with opposite sign. Two strategies discussed by Engeler are:

- accumulate absolute correlation magnitude; simple, but it discards coherent sign and therefore sacrifices noise averaging;
- correlate over the known **minute-start PM pattern** (seconds 0-14), which simultaneously resolves second and minute alignment and performs about **5 dB better** for equal acquisition time in the simulations.

The latter is the high-performance approach.

## Bit decisions

Once second timing is known:

- AM bit evidence comes from correlation with `AM_delta = AM1 - AM0` or an equivalent envelope decision;
- PM bit evidence comes from correlation with the PRN pattern and its inverse;
- after minute alignment, AM and PM evidence can be combined where the two encodings carry the same data.

Do not threshold too early. The ML decoder benefits materially from **soft values** rather than only hard 0/1 decisions.

## Fixed-point implementation guidance

The paper explicitly notes that the detector is suitable for fixed-point FPGA or microcontroller implementation. A practical RTL design should therefore expose and test the following independently:

- Goertzel state width and saturation policy;
- scaling multiplier precision;
- CORDIC angle/rotation precision;
- decimation/observation rates;
- soft-bit normalisation into approximately `[-1,+1]`;
- correlation accumulator width for one second and one minute;
- clock-error range over which the carrier Goertzel remains captured.

No exact HDL widths are published. They must be chosen from simulation using captured or synthetic DCF77 vectors.

## Reference rates from the demonstration receiver

The paper lists these internal periodic rates:

| Function | Rate |
|---|---:|
| ADC sampling | `12 f_c` = 930 kS/s |
| Goertzel result update | `f_c` = 77.5 kHz |
| PM correlation | `f_c / 20` = 3.875 kHz |
| time decoder | 1 Hz |

These are especially important because harmonics of these rates can leak through the board and antenna; see `05-clock-sync-noise.md`.
