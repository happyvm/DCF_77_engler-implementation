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

## Rev.0 component documentation download registry

Last link verification pass: **2026-09-08**.

This section is the download checklist for the hardware currently frozen in the Rev.0 HAT design. Prefer the direct manufacturer PDF/download URL. Product pages are retained as fallback locations because vendors sometimes replace direct document URLs when a revision changes.

A convenient local archive layout after manual download is `archive/datasheets/`. Suggested filenames below are deliberately stable and do not depend on vendor CDN naming.

### FPGA — Lattice `LFE5U-45F-7BG256I`

Main device documentation:

- ECP5 / ECP5-5G family data sheet, `FPGA-DS-02012`: <https://www.latticesemi.com/view_document?document_id=50461>
  - suggested file: `Lattice_ECP5_ECP5-5G_FPGA-DS-02012.pdf`
- Package diagrams, `FPGA-DS-02053`: <https://www.latticesemi.com/view_document?document_id=213>
  - suggested file: `Lattice_FPGA_Package_Diagrams_FPGA-DS-02053.pdf`
- ECP5U-45 pinout, `FPGA-SC-02034` (CSV): <https://www.latticesemi.com/view_document?document_id=50486>
  - suggested file: `Lattice_ECP5U-45_Pinout_FPGA-SC-02034.csv`
- ECP5-45F caBGA256 density/package data (CSV): <https://www.latticesemi.com/view_document?document_id=54147>
  - suggested file: `Lattice_ECP5-45F-CABGA256-DD.csv`
- Product/documentation page: <https://www.latticesemi.com/ECP5>

Configuration, clocking and PCB documents worth archiving with the FPGA data sheet:

- ECP5 / ECP5-5G sysCONFIG user guide, `FPGA-TN-02039`: <https://www.latticesemi.com/view_document?document_id=50462>
  - suggested file: `Lattice_ECP5_sysCONFIG_FPGA-TN-02039.pdf`
- ECP5 / ECP5-5G hardware checklist, `FPGA-TN-02038`: <https://www.latticesemi.com/view_document?document_id=50482>
  - suggested file: `Lattice_ECP5_Hardware_Checklist_FPGA-TN-02038.pdf`
- ECP5 / ECP5-5G sysCLOCK PLL/DLL guide, `FPGA-TN-02200`: <https://www.latticesemi.com/view_document?document_id=50465>
  - suggested file: `Lattice_ECP5_sysCLOCK_FPGA-TN-02200.pdf`
- ECP5 / ECP5-5G sysI/O guide, `FPGA-TN-02032`: <https://www.latticesemi.com/view_document?document_id=50464>
  - suggested file: `Lattice_ECP5_sysIO_FPGA-TN-02032.pdf`
- PCB layout recommendations for BGA packages, `FPGA-TN-02024`: <https://www.latticesemi.com/view_document?document_id=671>
  - suggested file: `Lattice_BGA_PCB_Layout_FPGA-TN-02024.pdf`
- Programming external SPI flash through JTAG for ECP5/ECP5-5G, `FPGA-TN-02050`: <https://www.latticesemi.com/view_document?document_id=52228>
  - suggested file: `Lattice_ECP5_SPI_Flash_via_JTAG_FPGA-TN-02050.pdf`
- Dual/multiple boot feature, `FPGA-TN-02203`: <https://www.latticesemi.com/view_document?document_id=39451>
  - suggested file: `Lattice_ECP5_Dual_Multiple_Boot_FPGA-TN-02203.pdf`

### Precision clock — SiTime `SiT5356AI-FQ-33E0-25.000000`

- Direct SiT5356 data sheet PDF endpoint: <https://www.sitime.com/datasheet/SiT5356>
  - suggested file: `SiTime_SiT5356_Datasheet.pdf`
- Product/resource page: <https://www.sitime.com/support/resource-library/datasheets/sit5356-datasheet>

The same family data sheet covers TCXO, VCTCXO and DCTCXO ordering modes. Rev.0 uses the fixed 25 MHz TCXO ordering choice documented elsewhere in this repository.

### Configuration flash — Winbond `W25Q64JVSSIQ`

- Direct Winbond W25Q64JV family data sheet PDF: <https://www.winbond.com/resource-files/w25q64jv%20revj%2003272018%20plus.pdf>
  - suggested file: `Winbond_W25Q64JV_Datasheet_RevJ.pdf`
- W25Q-JV family/product page: <https://www.winbond.com/hq/product/code-storage-flash/qspi-nor/w25q-jv/?__locale=en&partNo=W25Q64JVSSIQ>

Winbond's current documentation UI is dynamically generated; keep the direct Rev. J PDF locally even if the website later publishes a newer revision. Before fabrication, compare the archived revision with the then-current Winbond product page for PCNs or a newer data-sheet revision.

### Integrated ferrite antenna — TDK `B82453C0275A000`

- Direct TDK B82453C*A family data sheet PDF, includes the exact `B82453C0275A000` row: <https://product.tdk.com/system/files/dam/doc/product/inductor/inductor/transponder/data_sheet/30/ds/b82453c_a.pdf>
  - suggested file: `TDK_B82453C-A_Transponder_Coils.pdf`
- Exact TDK product page: <https://product.tdk.com/en/search/inductor/inductor/transponder/info?part_no=B82453C0275A000>

### Antenna/input buffer — TI `OPA810IDBVR`

- Direct OPA810 data sheet PDF: <https://www.ti.com/lit/ds/symlink/opa810.pdf>
  - suggested file: `TI_OPA810_Datasheet.pdf`
- Product page: <https://www.ti.com/product/OPA810>

### Analog band-pass filter — ADI/Linear Technology `LTC1562IG#PBF`

- Direct LTC1562 data sheet PDF: <https://www.analog.com/media/en/technical-documentation/data-sheets/1562fa.pdf>
  - suggested file: `ADI_LTC1562_Datasheet.pdf`
- Product page: <https://www.analog.com/en/products/ltc1562.html>

### Programmable gain amplifier — ADI/Linear Technology `LTC6912IGN-1#PBF`

- Direct LTC6912 data sheet PDF: <https://www.analog.com/media/en/technical-documentation/data-sheets/6912fa.pdf>
  - suggested file: `ADI_LTC6912_Datasheet.pdf`
- Product page: <https://www.analog.com/en/products/ltc6912.html>

The Rev.0 choice is the `-1` gain table: 0/1/2/5/10/20/50/100 V/V.

### ADC driver — TI `OPA2835IDGSR`

- Direct OPA2835 / OPAx835 data sheet PDF: <https://www.ti.com/lit/ds/symlink/opa2835.pdf>
  - suggested file: `TI_OPA2835_Datasheet.pdf`
- Product page: <https://www.ti.com/product/OPA2835>

### ADC — ADI/Linear Technology `LTC1407AIMSE-1#PBF`

- Direct LTC1407A-1 family data sheet PDF: <https://www.analog.com/media/en/technical-documentation/data-sheets/14071fb.pdf>
  - suggested file: `ADI_LTC1407A-1_Datasheet.pdf`
- Bipolar differential family product page: <https://www.analog.com/en/products/ltc1407-1.html>

The exact Rev.0 device is the 14-bit `LTC1407A-1`; do not substitute timing assumptions from the 12-bit non-A device.

### 5 V rail load switch — TI `TPS22975NDSGR`

- Direct TPS22975 data sheet PDF: <https://www.ti.com/lit/ds/symlink/tps22975.pdf>
  - suggested file: `TI_TPS22975_Datasheet.pdf`
- Product page: <https://www.ti.com/product/TPS22975>

### ADC analog LDO — ADI `LT3042EMSE#PBF`

- Direct LT3042 data sheet PDF: <https://www.analog.com/media/en/technical-documentation/data-sheets/lt3042.pdf>
  - suggested file: `ADI_LT3042_Datasheet.pdf`
- Product page: <https://www.analog.com/en/products/lt3042.html>

### Clock and auxiliary LDOs — TI `TPS7A2033PDQNR` and `TPS7A2025PDQNR`

Both orderable parts are covered by the TPS7A20 family data sheet.

- Direct TPS7A20 family data sheet PDF: <https://www.ti.com/lit/ds/symlink/tps7a20.pdf>
  - suggested file: `TI_TPS7A20_Datasheet.pdf`
- Product page: <https://www.ti.com/product/TPS7A20>

### FPGA core buck — TI `TPS628502DRLR`

- Direct TPS62850x/TPS628502 data sheet PDF endpoint: <https://www.ti.com/lit/gpn/TPS628502>
  - suggested file: `TI_TPS62850x_TPS628502_Datasheet.pdf`
- Product page: <https://www.ti.com/product/TPS628502>

### FPGA core buck inductor — Murata `DFE252012PD-R47M=P2`

- Direct Murata DFE252012PD series data sheet/download: <https://www.murata.com/-/media/webrenewal/products/inductor/chip/tokoproducts/wirewoundmetalalloychiptype/m_dfe252012pd.ashx?la=en>
  - suggested file: `Murata_DFE252012PD_Datasheet.pdf`
- Exact part is `0.47 uH`, `DFE252012PD-R47M=P2`.

### Local LCD — Newhaven `NHD-C0220BiZ-FSW-FBW-3V3M`

- Direct Newhaven product specification PDF: <https://newhavendisplay.com/content/specs/NHD-C0220BiZ-FSW-FBW-3V3M.pdf>
  - suggested file: `Newhaven_NHD-C0220BiZ-FSW-FBW-3V3M.pdf`
- Product page: <https://newhavendisplay.com/2x20-character-cog-lcd-fstn-display-with-white-backlight-and-mounting-holes/>

#### LCD controller — Sitronix `ST7036`

The controller is integrated into the selected Newhaven module; it is not a separately populated Rev.0 component, but its command/timing documentation is required by the FPGA LCD controller.

- ST7036 V1.8b data sheet, hosted by Newhaven support: <https://support.newhavendisplay.com/hc/en-us/article_attachments/8733961483287>
  - suggested file: `Sitronix_ST7036_V1.8b.pdf`
- Newhaven support page: <https://support.newhavendisplay.com/hc/en-us/articles/4414860535575-ST7036>

### HAT ID EEPROM — `CAT24C32`-compatible family, exact MPN not yet frozen

The pin plan currently recommends a CAT24C32-compatible device but does not freeze an exact orderable MPN. This is therefore a **candidate/family reference**, not permission to silently lock the BOM to one package.

- onsemi CAT24C32 family data sheet PDF: <https://www.onsemi.com/pdf/datasheet/cat24c32-d.pdf>
  - suggested file: `onsemi_CAT24C32_Datasheet.pdf`

### Raspberry Pi HAT+ electrical/mechanical interface

This is not a PCB component data sheet, but it is a fabrication-critical primary document for the Rev.0 board.

- Raspberry Pi HAT+ Specification PDF: <https://datasheets.raspberrypi.com/hat/hat_plus_specification.pdf>
  - suggested file: `Raspberry_Pi_HAT_Plus_Specification.pdf`

### Parts intentionally not assigned a data sheet yet

Do **not** invent manufacturer documents for these until the BOM freezes an exact MPN:

- HAT ID EEPROM package/orderable suffix beyond the CAT24C32-compatible recommendation;
- LCD backlight N-MOSFET;
- any HAT-side ESD/protection device not yet frozen;
- generic resistors and capacitors where only value/dielectric/tolerance are currently specified;
- optional external-antenna connector/link parts.

When any of these is frozen, add the exact MPN and direct manufacturer PDF here in the same commit as the BOM change.

## Manufacturer sources for the historical analog chain

### LTC1562

Analog Devices / Linear Technology, **LTC1562 — Very Low Noise, Low Distortion Active RC Quad Universal Filter**.

- Product: <https://www.analog.com/en/products/ltc1562.html>
- Data sheet: <https://www.analog.com/media/en/technical-documentation/data-sheets/1562fa.pdf>

The data sheet contains the 8th-order high-frequency band-pass application used to derive the first 77.5 kHz rebuild values in [`11-analog-reference-design.md`](11-analog-reference-design.md).

### LTC6912

Analog Devices / Linear Technology, **LTC6912 — Dual Programmable Gain Amplifiers with Serial Digital Interface**.

- Product: <https://www.analog.com/en/products/ltc6912.html>
- Data sheet: <https://www.analog.com/media/en/technical-documentation/data-sheets/6912fa.pdf>

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

When manually archiving manufacturer PDFs in this public repository, check the manufacturer's redistribution/licensing terms before committing the binary files. The links in this registry remain the authoritative provenance even when a local convenience copy is stored.