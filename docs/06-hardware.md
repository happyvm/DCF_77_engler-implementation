# Hardware recovered from the paper

## Published component inventory

The block diagram of the demonstration receiver identifies the following parts explicitly:

| Function | Part / specification in paper |
|---|---|
| ferrite antenna | HKW FTD02011R |
| antenna input device | BF245A JFET |
| analog band-pass | LTC1562, 8th-order filter |
| programmable gain | LTC6912 PGA |
| ADC | LTC1407, 14 bit, 930 kS/s |
| FPGA | Xilinx XC3S1400AN |
| debug DAC | LTC2624, 4 channel |
| history memory | 3600 s logical history in FPGA design |
| user output | LCD |
| debug/control | USB plus internal debug path |
| reference clock | oscillator, exact part not identified |

## Analog front-end requirements

### Ferrite antenna interface

The antenna is resonant and high impedance. The BF245A input stage should therefore be rebuilt as a low-noise, low-loading buffer/amplifier. The paper does **not** provide:

- ferrite coil inductance;
- resonating capacitor value;
- tap/coupling arrangement;
- BF245A source/drain resistor values;
- bias current;
- exact front-end gain;
- ESD/protection network.

These must be determined from the actual antenna or a substitute.

### Band-pass

The LTC1562 is stated to form an 8th-order band-pass, but the complete transfer function and external component values are not printed. The reconstruction should therefore first choose a target based on the detector needs:

- enough bandwidth for PM timing (the useful DCF77 main + first side-lobe bandwidth discussed in the paper is about 2583 Hz);
- strong rejection of nearby switched-mode-supply interference;
- known and preferably calibratable group delay.

Do not assume a 15 Hz analog filter merely because the AM digital Goertzel path has 15 Hz effective bandwidth. The analog path must preserve the PM waveform as well.

### PGA and dynamic range

The LTC6912 is FPGA-controlled. The paper uses a design assumption of up to **100 dB(µV/m)** maximum field strength plus **20 dB headroom** when considering the near-transmitter end of the dynamic range.

At the far/weak-signal end, simulation suggested that even a DCF77 amplitude of **1 ADC LSB** could be sufficient under noise; the hardware design chose about **2 LSB** as the minimum wanted-signal amplitude target.

This implies a very wide required gain range and argues for a deliberately slow AGC that responds to overall ADC headroom rather than to the 100/200 ms DCF77 AM pulse itself.

## ADC interface

The LTC1407 is clocked at **930 kS/s**. The FPGA must capture 14-bit samples with deterministic phase relative to its processing clock. Because the design disciplines its clock to DCF77, the ADC sampling rate becomes indirectly carrier locked after acquisition.

During initial reconstruction, store raw ADC bursts to USB or on-chip RAM before implementing the entire detector. Raw captures are essential for debugging filter tuning, gain and self-interference.

## FPGA functional blocks to recreate

The paper's block diagram identifies these digital functions:

- random sample-processing delay/buffering;
- automatic gain control;
- phase detection;
- clock synchronisation;
- PM/AM correlation;
- correlation accumulation;
- second detection;
- second synchronisation;
- 3600 s history storage;
- time decoding;
- debug capture/output;
- LCD interface;
- DAC debug outputs;
- USB interface.

The exact FPGA partitioning and buses are not published. A clean modern implementation should separate the design into streaming DSP blocks plus a lower-rate control/time-decoder domain.

## Modern-substitution policy

Recreating the *architecture* does not require sourcing every obsolete part unless exact historical reproduction is the goal. This repository should track two BOMs:

1. **reference BOM** — the exact parts named above;
2. **rebuild BOM** — currently available replacements with equivalent noise, bandwidth, ADC rate/resolution and FPGA resources.

Any replacement must preserve the observable interfaces needed by the algorithm: approximately 930 kS/s real samples around 77.5 kHz, stable timing, controllable gain and sufficiently low front-end noise.
