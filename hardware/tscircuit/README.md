# tscircuit hardware workspace

This directory is the authoritative source for DCF77 receiver schematic and PCB design intent.

The project produces **two PCB variants from one shared receiver core**:

1. Raspberry Pi Standard HAT+ — powered from the Raspberry Pi 5 V GPIO-header rail;
2. standalone board — powered from USB-C as a 5 V sink.

The analog front end, ADC, clock, ECP5, display/timing outputs and downstream receiver power tree should remain shared wherever possible.

## Current pin-level decisions

Now selected or strongly preferred for Rev.0:

```text
Antenna      TDK B82453C0275A000, X winding
Antenna C    560 pF + 22 pF C0G/NP0, fixed
Antenna R    330 kOhm damping, fixed
Input buffer OPA810IDBVR
BPF          LTC1562IG#PBF, fixed 77.5 kHz / 7.75 kHz design
PGA          LTC6912IGN-1#PBF, gains 0/1/2/5/10/20/50/100
TCXO         SiT5356AI-FQ-33E0-25.000000, 25 MHz, 3.3 V, ±100 ppb
FPGA         Lattice ECP5 LFE5U-45F, BG256 preferred
ADC          LTC1407AIMSE-1#PBF
ADC rate     930 kS/s
ADC driver   OPA2835IDGSR candidate, validation required
PPS          mandatory dedicated ECP5 hardware output
Display      transflective 20x2 LCD on both PCB variants
1V1 core     TPS628502 candidate
3V3 digital  TPS628502 candidate
2V5 aux      TPS7A20 fixed 2.5 V candidate
3V3 ADC      LT3042 candidate
3V3 clock    TPS7A20 fixed 3.3 V candidate
5V AFE       low-loss passively filtered 5V_SYS
```

The integrated antenna and LTC1562 filter are intentionally **no-trim**. Component values are fixed from tolerance analysis and manufacturer reference designs; per-board passive selection is not part of the reference build.

The PGA is fixed at the hardware level. Gain is selected digitally by ECP5 from the LTC6912-1 table; no analog gain trim exists. The AGC controls ADC headroom and must not chase the deliberate DCF77 AM reduction.

The TCXO OPN and nominal frequency are now fixed at 25 MHz. DCF77 frequency discipline remains digital in the ECP5/sample scheduler; no DCTCXO control bus is required in the reference design.

Still open before the complete `index.circuit.tsx` is frozen:

- exact regulator OPN/package/passives after power simulation and sourcing re-check;
- exact ECP5 speed/temperature OPN;
- SPI configuration flash;
- exact LCD OPN/mechanical arrangement;
- USB-C sink/power-path controller;
- Raspberry Pi GPIO assignments.

ADC details are in [`../../docs/18-adc-selection.md`](../../docs/18-adc-selection.md).
Power details are in [`../../docs/19-power-tree.md`](../../docs/19-power-tree.md).
Antenna/input details are in [`../../docs/20-antenna-input.md`](../../docs/20-antenna-input.md).
Fixed LTC1562 details are in [`../../docs/21-ltc1562-fixed-filter.md`](../../docs/21-ltc1562-fixed-filter.md).
PGA details are in [`../../docs/22-ltc6912-pga.md`](../../docs/22-ltc6912-pga.md).
Clock details are in [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md).

## Planned structure

```text
hardware/tscircuit/
  package.json
  tsconfig.json

  src/
    core/
      receiver_core.tsx
      afe.tsx
      adc.tsx
      ecp5.tsx
      clock.tsx
      display.tsx
      pps.tsx
      receiver_power.tsx

    variants/
      raspberry_pi_hatplus.tsx
      standalone_usb_c.tsx

    host/
      rpi_spi.tsx
      usb_debug.tsx

    power/
      hat_5v_input.tsx
      usb_c_5v_input.tsx

    parts/
      ... reusable symbols/footprints/part wrappers ...

    board/
      common_constraints.ts
      hatplus_constraints.ts
      standalone_constraints.ts
      quilter.ts

  dist/
    hatplus/
      circuit-json/
      kicad-pre-quilter/
      kicad-post-quilter/
      fabrication/

    standalone/
      circuit-json/
      kicad-pre-quilter/
      kicad-post-quilter/
      fabrication/
```

## Tooling policy

- **tscircuit TSX is the editable hardware source of truth.**
- Pin-accurate manufacturer data must be checked before part wrappers are committed.
- RF/mechanical hard placement constraints are encoded before automated layout.
- **Quilter is the selected placement/routing engine.**
- Each variant is exported from tscircuit to KiCad and submitted to a separate Quilter job with its own mechanical and RF constraints.
- Quilter returns native KiCad candidates for engineering review.
- A Quilter result is not fabrication-ready merely because it is routed or DRC-clean.
- Final KiCad inspection/DRC and Gerber review are mandatory before fabrication.
- Electrical/footprint/mandatory-placement changes discovered during KiCad/Quilter review must be represented back in tscircuit for the next iteration.

See [`../../docs/14-hardware-cad-tscircuit.md`](../../docs/14-hardware-cad-tscircuit.md) and [`../../docs/17-pcb-variants.md`](../../docs/17-pcb-variants.md).

## Shared power boundary

Both boards present the same internal `5V_SYS` boundary to the common receiver core.

Current downstream architecture:

```text
5V_SYS
  |
  +--> low-loss passive filter -> 5V_AFE
  |      -> OPA810 / LTC1562 / LTC6912
  |
  +--> LT3042 -> 3V3_ADC_A
  |      -> LTC1407A-1 / OPA2835
  |
  +--> TPS7A20 -> 3V3_CLK
  |      -> SiT5356 fixed TCXO
  |
  +--> TPS628502 -> 3V3_D
  |      -> ECP5 VCCIO / flash / LCD logic
  |      -> TPS7A20 -> 2V5_AUX
  |
  +--> TPS628502 -> 1V1_CORE
```

Only the 5 V input shell differs:

```text
HAT+:
Raspberry Pi 5V -> protected/gated input -> 5V_SYS

standalone:
USB-C VBUS -> Type-C sink/power path -> 5V_SYS
```

The HAT+ variant uses Raspberry Pi 3.3 V only for HAT identification / power-state sensing as required, not as the main FPGA/analog supply.

`3V3_D` is intentionally the first controlled FPGA rail. Its power-good signal enables `1V1_CORE` and `2V5_AUX` so ECP5 VCCIO8/configuration flash are valid before normal configuration begins.

## RF-critical placement policy

The following are not freely placed by Quilter:

- TDK B82453C0275A000 antenna orientation and board-edge position;
- fixed 560 pF + 22 pF C0G tuning capacitors and 330 kOhm damping resistor;
- OPA810 immediately beside the active X winding input node;
- LTC1562 and all fixed programming resistors;
- LTC6912 and its AGND/input coupling parts;
- ADC, LT3042, OPA2835 and the input RC network as a tight cluster;
- SiT5356 TCXO and its dedicated TPS7A20/clock escape direction;
- switcher hot loops and inductors;
- mounting holes;
- mechanically fixed board-edge connectors.

No fast clock, USB, SPI, ADC serial clock or buck switch node may run under or beside the integrated ferrite/input cluster. The unused Y/Z antenna windings remain open and must not acquire long PCB stubs.

PGA SPI is sparse and low-rate; it must still be routed away from the ferrite and active-filter section nodes.

The 25 MHz TCXO trace must remain short and must not cross the AFE/ferrite region.

Analog, ADC, clock, FPGA, LCD, USB/debug and power blocks receive placement regions/keepouts so Quilter optimizes within the intended RF floorplan rather than inventing the floorplan itself.

The HAT+ and standalone boards have different interference environments, so their placement constraints are variant-specific even though the receiver topology is shared.

## Raspberry Pi HAT+ variant

- follow the current HAT+ specification;
- powered from Raspberry Pi 5 V header pins;
- never source power back into the Pi;
- generate all major receiver rails locally from 5 V;
- design for Raspberry Pi `STANDBY`, where 5 V can remain present while 3.3 V is off;
- gate the main receiver power tree from Raspberry Pi active/3.3-V presence unless an explicit always-on option is selected;
- reserve the HAT+ identification EEPROM interface;
- preferred Pi/ECP5 runtime transport is SPI + interrupt/status;
- expose the same dedicated external PPS as the standalone board, with an optional copy to a Pi GPIO.

## Standalone USB-C variant

- USB-C is initially a 5 V sink;
- USB-PD is optional only if measured power requires it;
- use a controlled Type-C power path/load switch/eFuse;
- USB 2.0 data through the same connector is optional and independent of the receiver core;
- retain JTAG, dedicated PPS and a debug/control interface so the board is useful without a Raspberry Pi.

## Clock selection

Reference Rev.0 clock source:

```text
SiT5356AI-FQ-33E0-25.000000
25 MHz
3.3 V LVCMOS
±100 ppb
-40...+85 degC
```

Reference plan:

```text
25 MHz TCXO
  -> ECP5 PLL
  -> 125 MHz nominal system clock
  -> 40-bit fractional sample/time scheduler
  -> 930 kS/s average ADC cadence
  -> digitally disciplined PPS
```

DCTCXO remains an experimental option only. See [`../../docs/15-sitime-super-tcxo.md`](../../docs/15-sitime-super-tcxo.md).

## Antenna/input block

Reference Rev.0 integrated input:

```text
TDK B82453C0275A000 X winding
  || 560 pF C0G
  || 22 pF C0G
  || 330 kOhm
       |
       +--> ANT_IN
              |
              +--> OPA810 voltage follower @ 5V_AFE
                       |
                       +--> LTC1562 fixed BPF
```

The resonant network is centered around a quiet 2.5 V `VCM_AFE` node. The fixed values target approximately 586 pF total capacitance after the OPA810/PCB input-capacitance budget is included.

There is no reference-BOM trimmer. Prototype measurements validate the calculation but do not determine per-board component values.

## Filter/PGA block

Reference Rev.0:

```text
LTC1562IG#PBF
  -> fc 77.5 kHz, BW ~7.75 kHz, gain ~10
  -> 1.0 uF AC coupling
  -> LTC6912IGN-1#PBF channel A
  -> digital gains 1/2/5/10/20/50/100
```

Channel B is software-shutdown by default.

After second synchronization, gain changes occur only near ~995 ms after the second boundary, after the PM sequence has ended. The AGC estimates amplitude in the 250...950 ms stable-carrier region and does not respond to the 100/200 ms DCF77 AM reduction.

## ADC block

Preferred Rev.0 chain:

```text
LTC6912 output
  -> AC coupling / 1.25 V rebias
  -> OPA2835 channel @ 3V3_ADC_A
  -> 51 ohm + 47 pF C0G isolation
  -> LTC1407A-1 CH0

LTC1562 diagnostic source
  -> OPA2835 channel @ 3V3_ADC_A
  -> 51 ohm + 47 pF C0G isolation
  -> LTC1407A-1 CH1
```

The ADC and OPA2835 share a dedicated LT3042-derived 3.3 V analog rail. The 2.5 V ADC internal reference is locally bypassed and divided to create the 1.25 V ADC common-mode node.

## FPGA resource policy

The physical board may use an ECP5 LFE5U-45F for availability and debugging headroom, but the reference receiver build must stay within the historical XC3S1400AN resource envelope.

Machine-readable limits:

[`../../rtl/resource_budget.json`](../../rtl/resource_budget.json)
