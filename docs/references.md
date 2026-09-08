# References

## Primary receiver paper

Daniel Engeler, **Performance Analysis and Receiver Architectures of DCF77 Radio-Controlled Clocks**, IEEE Transactions on Ultrasonics, Ferroelectrics, and Frequency Control, vol. 59, no. 5, May 2012, pp. 869-884. DOI: `10.1109/TUFFC.2012.2272`.

A draft copy used to prepare this repository documentation is archived at:

- [`../archive/papers/Engeler_DCF77.pdf`](../archive/papers/Engeler_DCF77.pdf)

## Primary DCF77 / PTB sources

### Piester, Hetzel, Bauch — PTB 2004

D. Piester, P. Hetzel, A. Bauch, **Zeit- und Normalfrequenzverbreitung mit DCF77**, PTB-Mitteilungen 114 (2004), Heft 4.

Direct PTB PDF:

- <https://www.ptb.de/cms/fileadmin/internet/fachabteilungen/abteilung_4/4.4_zeit_und_frequenz/pdf/2004_Piester_-_PTB-Mitteilungen_114.pdf>

Especially important for this project:

- section 4.3: PRN/PZF phase modulation;
- figure 7: AM/PM timing within one second;
- figure 8: 9-stage feedback register with stages 5 and 9 fed back;
- PRN clock `77,500/120 Hz`;
- ten inverted sequences at seconds 0-9 for minute identification;
- receive-bandwidth discussion for PRN correlation.

### Hetzel — EFTF 1988

P. Hetzel, **Time dissemination via the LF transmitter DCF77 using a pseudo-random phase-shift keying of the carrier**, 2nd European Frequency and Time Forum, Neuchâtel, 1988.

Public mirror used during reconstruction:

- <https://embedded.fel.cvut.cz/sites/default/files/kurzy/lpe/radioclock_dcf77/docs/Hetzel_DCFBPSK_1988_EFTF.pdf>

This source gives the transmitter implementation in unusually concrete form: the feedback shift register, auxiliary flip-flop for escaping the all-zero state, sequence inversion keying, chip duration and timing inside each second.

## Manufacturer sources for the historical analog chain

### LTC1562

Analog Devices / Linear Technology, **LTC1562 — Very Low Noise, Low Distortion Active RC Quad Universal Filter**.

- Product: <https://www.analog.com/en/products/ltc1562.html>
- Data sheet: <https://www.analog.com/media/en/technical-documentation/data-sheets/1562fa.pdf>

The data sheet contains the 8th-order high-frequency band-pass application used to derive the first 77.5 kHz rebuild values in [`11-analog-reference-design.md`](11-analog-reference-design.md).

### LTC6912

Analog Devices / Linear Technology, **LTC6912 — Dual Programmable Gain Amplifiers with Serial Digital Interface**.

- Product/data: <https://www.analog.com/en/products/ltc6912.html>

Relevant facts include the two gain-table variants:

- LTC6912-1: 0/1/2/5/10/20/50/100 V/V;
- LTC6912-2: 0/1/2/4/8/16/32/64 V/V.

### LTC1407 family

Analog Devices / Linear Technology, **LTC1407 / LTC1407A** and **LTC1407-1 / LTC1407A-1** simultaneous-sampling ADC family.

- LTC1407 family: <https://www.analog.com/en/products/ltc1407.html>
- bipolar differential family: <https://www.analog.com/en/products/ltc1407-1.html>
- LTC1407A-1 data sheet family PDF: <https://www.analog.com/media/en/technical-documentation/data-sheets/14071fb.pdf>

Important reconstruction detail: the `A` variants are 14-bit, while the non-A LTC1407 devices are 12-bit.

### BF245A

NXP/Philips, **BF245A/B/C N-channel silicon field-effect transistors**.

- Product page: <https://www.nxp.com/products/BF245A>
- Data sheet: <https://www.nxp.com/docs/en/data-sheet/BF245A-B-C.pdf>

The BF245A is discontinued. Manufacturer data confirms the broad device spread that makes the unpublished original bias network important to measure rather than guess.

## Secondary antenna source

A useful independent comparison of DCF77 receiver modules and HKW ferrite antennas is available at:

- <https://blog.blinkenlight.net/experiments/dcf77/dcf77-receiver-modules/>

It reports approximately 897 µH and ~700 Hz bandwidth for several HKW ferrite-rod antenna variants, based on HKW data sheets. This is **secondary evidence only** and must not be treated as proof of the exact FTD02011R values used on Engeler's board.

## Other references cited by Engeler

The Engeler paper cites further sources important for detector theory and performance analysis, including:

1. J. Wietzke, receiver-performance criteria for time-signal receivers.
2. E. Jacobsen and R. Lyons, **The Sliding DFT**, IEEE Signal Processing Magazine, 2003.
3. C. Kandziora and R. Weigel, low-power sub-microsecond time synchronisation.
4. W. J. Pelgrum, low-frequency radionavigation.
5. R. Mohr and M. Schubert, technology/development of radio-controlled clocks.
6. M. Wierich, digital high-sensitivity DCF77 receiver diploma thesis.
7. K. Kalliomäki et al., using DCF77/NTP servers to control carrier frequencies of base stations.
8. ITU-R P.372, **Radio noise**.
9. L. T. Smit et al., soft-output bit-error-rate estimation.
10. LTspice documentation/model environment used for the receiver-noise simulation.

## Source-handling policy

The Markdown documents in this repository are an implementation-oriented engineering reconstruction, not a verbatim reproduction of the cited papers.

Every technical statement should be classed mentally as one of:

- **paper fact** — explicitly present in Engeler;
- **primary-source fact** — recovered from PTB or another authoritative source;
- **manufacturer fact** — taken from the component data sheet;
- **reconstruction choice** — selected by this project to make a buildable implementation;
- **secondary evidence** — useful lead that still requires validation.

This distinction prevents inferred hardware details from silently turning into false historical facts.