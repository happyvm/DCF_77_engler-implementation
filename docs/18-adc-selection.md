# Rev.0 ADC and input-driver selection

## Decision

For Rev.0, keep the ADC architecture closest to Engeler instead of replacing a component that is still actively manufactured and well stocked.

Preferred ADC:

```text
Analog Devices LTC1407AIMSE-1#PBF
14 bit
2 simultaneous channels
±1.25 V differential input range
1.5 MS/s per channel maximum
3-wire serial interface
MSOP-10 exposed pad
industrial temperature grade
```

The device is currently listed by Analog Devices as **PRODUCTION**. A September 2026 distributor snapshot showed roughly 1.1k pieces of the industrial `-1` variant at Mouser. The non-`-1` LTC1407A family is also in production and shares the same package/pin family.

This is therefore a case where historical fidelity and lifecycle practicality currently point in the same direction.

The exact suffix used by Engeler remains historically unknown. Selecting `LTC1407AIMSE-1#PBF` is a rebuild choice.

## Why not replace it with a modern 16-bit SAR immediately?

Modern candidates were evaluated, including:

- AD7980: 16 bit, 1 MS/s, production;
- ADAQ7980: 16 bit, 1 MS/s integrated driver/data-acquisition subsystem, recommended for new designs;
- ADS8860: 16 bit, 1 MS/s, active;
- newer dual simultaneous ADCs such as AD7380/ADS9224R.

They are technically attractive, but none currently provides enough system benefit to justify moving away from the still-production LTC1407A family for Rev.0.

Keeping LTC1407A-1 gives:

- the same 14-bit class as the paper;
- two simultaneous channels;
- an internal 2.5 V reference;
- a small leaded MSOP package;
- a simple serial interface;
- 930 kS/s operation comfortably below the 1.5 MS/s/channel rating;
- direct comparability with the historical receiver;
- no external high-precision reference requirement for first bring-up.

A 16-bit replacement remains an escape path if lifecycle or measured performance later justifies it.

## Input range and output format

For the `LTC1407A-1`:

```text
differential input span = -1.25 V ... +1.25 V
full span               = 2.5 V
resolution              = 14 bit
LSB                     = 2.5 V / 16384
                        ≈ 152.6 uV
output coding           = two's complement
```

The physical input pins must remain between ground and VDD even though the differential quantity is bipolar.

The non-`-1` LTC1407A uses the same 2.5 V span but outputs natural binary for a unipolar differential range. Keep this coding difference isolated in the ADC interface RTL.

## ADC supply

Use a dedicated low-noise 3.3 V rail:

```text
3V3_ADC_A -> LTC1407A-1 VDD
```

The family permits 2.7 V to 3.6 V operation. Using 3.3 V simplifies the electrical interface to a 3.3 V ECP5 I/O bank while keeping the ADC on its own filtered/low-noise analog supply.

Do not power the ADC directly from the noisy FPGA 3.3 V rail merely because the nominal voltage is the same.

Local bypass target:

```text
VDD  -> 10 uF + 100 nF close to the ADC
VREF -> 10 uF + 100 nF close to the ADC
```

Follow the manufacturer grounding recommendation around the exposed pad and keep ADC analog and digital current-return geometry explicit.

## 1.25 V ADC common-mode node

The internal reference is nominally 2.5 V. Generate a quiet midpoint for the bipolar input interface:

```text
VREF 2.5 V
   |
  4.99k
   +---- VCM_ADC ~= 1.25 V
  4.99k
   |
  AGND

VCM_ADC -> 1 uF || 100 nF to AGND
```

Use precision matched resistors. The midpoint is primarily a low-frequency bias reference; substantial local capacitance gives it a low AC impedance.

## ADC driver candidate

Preferred Rev.0 driver candidate:

```text
Texas Instruments OPA2810IDR
2 channels
FET input
RRIO
~105 MHz small-signal bandwidth
70 MHz GBW
~6 nV/sqrt(Hz) broadband voltage noise
5 V analog supply
SOIC-8
```

TI lists the OPA2810 as ACTIVE. Digi-Key showed roughly 900 pieces of the SOIC `OPA2810IDR` in stock in the September 2026 snapshot.

This is a **rebuild choice**, not an Engeler component.

The OPA2810 is attractive because it is easy to assemble, comfortably exceeds the LTC1407A input-drive bandwidth guidance, and gives two channels for the two simultaneous ADC inputs.

Do not freeze it into the production BOM until settling, noise and RF self-interference are validated on the prototype.

## Proposed channel-0 signal interface

The LTC6912 operating from 5 V is naturally referenced near half supply (~2.5 V). The `LTC1407A-1` input interface is cleaner if the ADC is biased around `VCM_ADC ~= 1.25 V`.

Use AC coupling and rebiasing:

```text
LTC6912 OUTA
     |
     C_AC
     |
     +------ 100k ------ VCM_ADC
     |
 OPA2810 A
 voltage follower
     |
    51R
     +---------------- CH0+
     |
    47pF C0G
     |
    AGND

VCM_ADC -- 51R -------- CH0-
                    |
                   47pF C0G
                    |
                   AGND
```

Starting value:

```text
C_AC = 100 nF C0G/NP0 preferred
```

With 100 kOhm bias impedance this coupling pole is only about 16 Hz, negligible compared with 77.5 kHz while keeping coupling-capacitor phase error very small.

The exact capacitor value may be adjusted based on obtainable C0G packages and measured phase response.

## Why the 51 ohm / 47 pF network is retained

The LTC1407A data sheet recommends a small series resistor plus local capacitor at the ADC input to:

- provide a local charge reservoir for the sample/hold;
- isolate upstream circuitry from sampling kickback;
- reduce wideband noise presented to the ADC;
- keep source impedance controlled.

The manufacturer example uses approximately:

```text
Rseries = 51 ohm
Cshunt  = 47 pF
```

Use C0G/NP0 capacitors and low-distortion metal-film/thin-film resistors.

At the project's 930 kS/s rate there is substantially more acquisition time than at the ADC's maximum throughput, so the input-driver settling requirement has useful margin.

## Channel 1: diagnostic simultaneous capture

Do not waste the second simultaneous ADC channel.

Provision channel 1 as a configurable diagnostic input. Candidate stuffing options:

```text
A: band-pass output before PGA
B: second PGA channel output
C: external analog test input
D: quiet reference / self-noise experiment
```

Route the selected source through the second OPA2810 channel and the same 51 ohm / 47 pF ADC input network.

The default Rev.0 stuffing choice should be selected when the final analog schematic is assembled. Avoid adding long high-impedance routes merely to support every option.

## Digital interface timing

At the target sample rate:

```text
Fs = 930,000 samples/s
Ts = 1.075268817 us
```

The dual conversion result is transmitted in 32 serial clocks. Therefore the average minimum raw bit-clock rate is:

```text
32 * 930 kHz = 29.76 MHz
```

Do not operate this close to the boundary. The ECP5 ADC wrapper should target a serial clock comfortably above 30 MHz and within the data-sheet timing limits, with enough margin for conversion and framing time.

Initial RTL requirement:

```text
CONV          exactly one event per disciplined ADC sample
SCK           > 30 MHz, final value derived from the selected FPGA clock plan
SDO           capture 32 bits = CH0 + CH1
sample_valid  asserted only after a complete frame
```

Keep physical ADC timing inside the platform wrapper. The detector core receives normalized signed channel samples and should not know the converter's serial protocol.

## Recommended RTL boundary

```text
rtl/platform/adc_if.sv
    -> signed ch0_sample[13:0]
    -> signed ch1_sample[13:0]
    -> sample_valid
    -> adc_fault

rtl/core/
    -> consumes signed normalized samples
```

If the pin-compatible unipolar LTC1407A is populated, the platform layer converts natural binary to the same signed internal representation.

## Rev.0 signal chain after this decision

```text
ferrite antenna
  -> high-Z input stage (still open)
  -> LTC1562 reference BPF
  -> LTC6912 PGA
  -> AC coupling / 1.25 V rebias
  -> OPA2810 dual driver candidate
  -> 51R / 47pF input isolation
  -> LTC1407AIMSE-1#PBF @ 930 kS/s
  -> ECP5
```

## Validation gates before PCB release

1. Measure OPA2810 output settling into the ADC network at 930 kS/s.
2. Verify no visible sampling-kickback corruption at the PGA output.
3. Measure ADC-code noise with input shorted to `VCM_ADC`.
4. Inject 77.5 kHz and verify phase versus amplitude/gain setting.
5. Confirm no clipping across all intended PGA gains.
6. Measure channel-to-channel phase/skew if channel 1 is used diagnostically.
7. Compare internal-reference noise against an external-reference experiment only if required.
8. Verify the ADC digital interface at worst-case clock/temperature corners.
9. Measure self-generated spurs at the ferrite input with CONV/SCK active.

## Lifecycle policy

The ADC is retained because current evidence says it is still production and stocked, not merely because it is historically authentic.

At every BOM release re-check:

- ADI lifecycle status for the exact OPN;
- Digi-Key/Mouser stock depth;
- lead time and PCNs;
- availability of the pin-compatible family variant;
- status of the modern 16-bit fallback candidates.

If the LTC1407A family moves to NRND/LTB/EOL or sourcing depth becomes poor, reopen the 16-bit SAR migration rather than buying large quantities of obsolete stock.

## Sources

- Analog Devices LTC1407/LTC1407A product page and data sheet.
- Analog Devices LTC1407-1/LTC1407A-1 product page and data sheet.
- Analog Devices DC1082A evaluation-board documentation.
- Texas Instruments OPA2810 product page and data sheet.
- September 2026 Digi-Key/Mouser availability snapshots used only as dated sourcing evidence.
