# Rev.0 LCD display selection

## Decision

The Raspberry Pi HAT+ uses the following local display:

```text
Newhaven Display NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 characters
FSTN transflective
white LED backlight
3.3 V logic
I2C interface
ST7036 controller
```

The local display remains available independently of Linux software state once the FPGA is running, and it is not required for timing operation.

## Electrical interface

```text
VDD = 3V3_D = PI_3V3
GND = board ground
SDA = ECP5 I2C-compatible GPIO
SCL = ECP5 I2C-compatible GPIO
RST = ECP5 GPIO
```

Provide local:

```text
100 nF
+ 1 uF
```

Use slow I2C operation, nominally 100 kHz, and avoid unnecessary updates.

## Display update policy

To minimize self-generated RF noise:

- do not continuously rewrite the full display;
- update only changed characters;
- normal time display may update once per second;
- diagnostic fields may update more slowly;
- avoid I2C transactions during sensitive receive intervals where practical.

## Reference screen

Example:

```text
12:34:56  DCF LOCK
08-09-26  Q:087 PM
```

Useful status fields include:

```text
hh:mm:ss
date
carrier lock
AM lock
PM/PZF lock
frame/minute lock
signal quality
holdover status
```

## Backlight

The white LED backlight is electrically separate from LCD logic.

Newhaven specifies approximately:

```text
VLED typ ~3.0 V
Iled typ ~30 mA
Iled max ~35 mA
```

The backlight must be current-limited externally.

Rev.0 policy:

```text
RF precision mode: backlight OFF
normal user mode:  backlight ON at fixed current
```

Do not use continuous high-frequency PWM by default.

Reference power path:

```text
5V_SYS
  -> fixed current-limiting network
  -> LCD backlight anode
LCD backlight cathode
  -> small N-MOSFET
  -> GND
```

The ECP5 drives the MOSFET with a static ON/OFF signal. Backlight current is intentionally not taken from the Pi 3.3 V rail.

## Rev.0 backlight design values (frozen)

Using the Newhaven figures above (VLED ~3.0 V typ, Iled ~30 mA typ, 35 mA max) and a small
logic-level N-MOSFET with Vds(on) ~0.15 V at 30 mA:

```text
target ~28 mA nominal, hard ceiling <= 35 mA over PI_5V 4.75..5.25 V and Vf 2.9..3.2 V

RBL1 = (5.00 - 3.00 - 0.15) / 0.028 = 66.1 ohm -> 68 ohm (E24), 0805
worst case = (5.25 - 2.90 - 0.05) / 68 = 33.8 mA   (<= 35 mA)
dimmest    = (4.75 - 3.20 - 0.15) / 68 = 20.6 mA
RBL1 power = 33.8 mA^2 * 68 = 78 mW (0805 = 125 mW, margin held)

RBL2 = 10 kOhm series gate resistor
RBL3 = 100 kOhm gate pull-down, holds the backlight OFF while the ECP5 is
       unconfigured, in reset or tri-stated (OFF is the safe precision-RF state)
LCD_BLQ = BSS138 logic-level N-MOSFET (Vgs(th) <= 1.5 V), SOT-23
```

A shorted LED would dissipate ~0.4 W in RBL1; the thick-film part fails open, i.e. fail-safe
with the backlight off, which is acceptable for this instrument.

## Mechanical policy

Approximate module dimensions:

```text
outline      ~75.7 x 27.1 mm
viewing area ~61 x 15.1 mm
```

The LCD is a mechanical constraint, not a part Quilter may move freely.

HAT-specific rules:

- lock LCD position/orientation before automated placement;
- keep ferrite as far as practical from display/backlight wiring;
- do not route I2C beneath the integrated ferrite;
- keep backlight return current out of the analog input region;
- verify Raspberry Pi clearance; overhang or a mechanically fixed daughter/front-panel arrangement is acceptable if required.

## Lifecycle/sourcing

September 2026 distributor checks showed the exact module active with several thousand units available. Recheck before BOM release.

## References

- Newhaven Display NHD-C0220BIZ-FSW-FBW-3V3M data sheet.
- ST7036 controller documentation.
