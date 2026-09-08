# References

## Primary source

Daniel Engeler, **Performance Analysis and Receiver Architectures of DCF77 Radio-Controlled Clocks**, IEEE Transactions on Ultrasonics, Ferroelectrics, and Frequency Control, vol. 59, no. 5, May 2012, pp. 869-884. DOI: `10.1109/TUFFC.2012.2272`.

A draft copy used to prepare this repository documentation is archived at:

- [`../archive/papers/Engeler_DCF77.pdf`](../archive/papers/Engeler_DCF77.pdf)

## References especially relevant to reconstruction

The Engeler paper cites the following sources as important background for the implementation. Titles are retained here so the missing engineering details can be traced deliberately rather than guessed.

1. D. Piester et al., dissemination of time and standard frequency using DCF77.
2. A. Bauch et al., dissemination of time and frequency using DCF77, historical overview.
3. P. Hetzel, time dissemination via DCF77 using pseudo-random phase-shift keying.
4. P. Hetzel, dissertation on long-wave time dissemination using AM time signals and pseudo-random carrier phase shifting.
5. J. Wietzke, receiver-performance criteria for time-signal receivers.
6. E. Jacobsen and R. Lyons, **The Sliding DFT**, IEEE Signal Processing Magazine, 2003.
7. C. Kandziora and R. Weigel, low-power sub-microsecond time synchronisation.
8. W. J. Pelgrum, low-frequency radionavigation in the 21st century.
9. R. Mohr and M. Schubert, technology/development of radio-controlled clocks.
10. M. Wierich, digital high-sensitivity DCF77 receiver diploma thesis.
11. K. Kalliomäki et al., using DCF77/NTP servers to control carrier frequencies of base stations.
12. ITU-R P.372, **Radio noise**.
13. L. T. Smit et al., soft-output bit-error-rate estimation.
14. LTspice documentation/model environment used for the receiver-noise simulation.

## Source-handling note

The Markdown documents in this repository are an implementation-oriented paraphrase and engineering reorganisation of the paper, not a verbatim reproduction. Numeric design targets, component names and algorithmic relationships are preserved because they are required to recreate and test the receiver.
