# Rev.0 LCD display selection

## Decision

Both PCB variants use the same Rev.0 display module:

```text
Newhaven Display NHD-C0220BIZ-FSW-FBW-3V3M
20 x 2 characters
FSTN
transflective
white LED backlight
3.3 V logic
I2C interface
ST7036 controller
```

The module is currently active and very well stocked at major distributors.

The display is intentionally common between:

- Raspberry Pi HAT+ board;
- standalone USB-C board.

The local time/status display therefore remains available even when the Raspberry Pi host or USB debug interface is unavailable.

## Electrical interface

Use:

```text
VDD = 3V3_D
GND = board ground
SDA = ECP5 I2C-compatible GPIO
SCL = ECP5 I2C-compatible GPIO
RST = ECP5 GPIO or deterministic RC/reset logic
```

The module supply range covers 3.3 V operation and its logic current is small compared with the FPGA rails.

Provide local:

```text
100 nF
+ 1 uF
```

near the module connector/pins.

I2C pull-ups belong on the board side and should be sized for deliberately slow edges rather than maximum bus speed. Reference operation should use a low bus rate such as 100 kHz unless a faster rate is shown to be harmless in EMI testing.

The display is a slow human interface; there is no reason to clock it aggressively.

## Display update policy

To minimize self-generated RF noise:

- do not continuously rewrite the full display;
- update only characters that have changed;
- normal time display may update once per second;
- diagnostic fields may update more slowly;
- avoid I2C transactions during the most sensitive receive intervals where convenient.

The LCD memory retains characters without continuous host traffic, so the digital interface can remain idle most of the time.

## Reference screen layout

Example normal view:

```text
12:34:56  DCF LOCK
08-09-26  Q:087 PM
```

Exact labels are firmware/RTL policy, but the display interface should expose at least:

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

The white backlight is separate from the LCD logic.

Newhaven specifies approximately:

```text
VLED typ ~3.0 V
Iled typ ~30 mA
Iled max ~35 mA
```

The backlight must therefore be current-limited externally; the module does not contain the required series resistor.

Rev.0 policy:

```text
RF precision mode: backlight OFF
normal user mode:  backlight ON at fixed current
```

Do not use continuous high-frequency PWM by default.

Preferred hardware implementation:

```text
3V3_D
  -> calculated/current-limited LED feed
  -> LCD backlight anode
LCD backlight cathode
  -> small N-MOSFET
  -> GND
```

The ECP5 controls the MOSFET with a static ON/OFF signal.

If brightness control is ever added, it must be validated spectrally at the ferrite input before becoming part of the reference design.

## Mechanical policy

The display is mechanically large compared with the receiver electronics:

```text
module outline approximately 75.7 x 27.1 mm
viewing area approximately 61 x 15.1 mm
```

It therefore acts as a board/enclosure constraint, not a component Quilter may freely move.

For both variants:

- lock LCD position/orientation before automated placement;
- keep the ferrite as far as practical from the backlight wiring and display connector;
- do not route display I2C beneath the integrated ferrite;
- keep backlight return current out of the analog input region.

The HAT+ mechanical arrangement may require the LCD to overhang or use a front-panel daughter/connector arrangement depending on final Raspberry Pi clearance. Electrical interface remains identical.

## Lifecycle/sourcing snapshot

September 2026 distributor checks showed the exact module active with several thousand units immediately available at Digi-Key.

Recheck before BOM release, but the current sourcing depth is substantially better than many FPGA/precision-clock parts in the design.

## References

- Newhaven Display NHD-C0220BIZ-FSW-FBW-3V3M data sheet.
- ST7036 controller documentation.
- September 2026 Digi-Key availability snapshot.
