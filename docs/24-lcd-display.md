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
