/**
 * Raspberry Pi Standard HAT+ mechanical interface.
 *
 * docs/14 "Locked before Quilter": the 40-pin connector and the mounting
 * holes/outline are locked; docs/27 §7-§9 fix the GPIO mapping and the pins that
 * Rev.0 intentionally leaves free; docs/27 §8 defines the HAT+ ID EEPROM.
 *
 * Physical pin names follow the Raspberry Pi 40-pin layout, odd pins on row 1.
 */
import { N } from "../parts/nets";
import { HAT_HEADER, MOUNTING_HOLES } from "./hatplus_constraints";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";

const GND = N.gnd;

const HAT_PIN_NAMES: Record<number, string> = {
  1: "PIN1_3V3", 2: "PIN2_5V", 3: "PIN3_GPIO2", 4: "PIN4_5V", 5: "PIN5_GPIO3",
  6: "PIN6_GND", 7: "PIN7_GPIO4", 8: "PIN8_GPIO14_TXD", 9: "PIN9_GND",
  10: "PIN10_GPIO15_RXD", 11: "PIN11_GPIO17", 12: "PIN12_GPIO18", 13: "PIN13_GPIO27",
  14: "PIN14_GND", 15: "PIN15_GPIO22", 16: "PIN16_GPIO23", 17: "PIN17_3V3",
  18: "PIN18_GPIO24", 19: "PIN19_GPIO10_MOSI", 20: "PIN20_GND",
  21: "PIN21_GPIO9_MISO", 22: "PIN22_GPIO25", 23: "PIN23_GPIO11_SCLK",
  24: "PIN24_GPIO8_CE0", 25: "PIN25_GND", 26: "PIN26_GPIO7_CE1",
  27: "PIN27_GPIO0_ID_SD", 28: "PIN28_GPIO1_ID_SC", 29: "PIN29_GPIO5",
  30: "PIN30_GND", 31: "PIN31_GPIO6", 32: "PIN32_GPIO12", 33: "PIN33_GPIO13",
  34: "PIN34_GND", 35: "PIN35_GPIO19", 36: "PIN36_GPIO16", 37: "PIN37_GPIO26",
  38: "PIN38_GPIO20", 39: "PIN39_GND", 40: "PIN40_GPIO21",
};

export const HAT_PIN_LABELS: Record<string, string> = Object.fromEntries(
  Object.entries(HAT_PIN_NAMES).map(([pin, name]) => [`pin${pin}`, name]),
);

export function HatHeader() {
  const connections: Record<string, string> = {
    PIN1_3V3: N.pi3v3,
    PIN17_3V3: N.pi3v3,
    PIN2_5V: N.pi5v,
    PIN4_5V: N.pi5v,
    // DCF77 host interface (through the series/damping network in host/rpi_spi.tsx)
    PIN7_GPIO4: N.ppsPi,
    PIN8_GPIO14_TXD: N.uartRxPi,
    PIN10_GPIO15_RXD: N.uartTxPi,
    PIN18_GPIO24: N.resetPi,
    PIN19_GPIO10_MOSI: N.spiMosiPi,
    PIN21_GPIO9_MISO: N.spiMisoPi,
    PIN22_GPIO25: N.irqPi,
    PIN23_GPIO11_SCLK: N.spiSclkPi,
    PIN24_GPIO8_CE0: N.spiCsPi,
    // HAT+ ID EEPROM bus, never connected to the ECP5
    PIN27_GPIO0_ID_SD: N.idSd,
    PIN28_GPIO1_ID_SC: N.idSc,
  };
  for (const [pin, name] of Object.entries(HAT_PIN_NAMES)) {
    if (name.endsWith("_GND")) connections[name] = GND;
    void pin;
  }

  return (
    <>
      <chip
        name="J1"
        pcbX={HAT_HEADER.x}
        pcbY={HAT_HEADER.y}
        pcbRotation={HAT_HEADER.rotation}
        pinLabels={HAT_PIN_LABELS}
        connections={connections}
      >
        {/* 2 x 20 through-hole header, 2.54 mm pitch, 48.26 x 2.54 mm.
            Odd pins on the row nearer the board edge, even pins opposite.
            A custom footprint is used because the generic row footprint would be
            1 x 40 (101 mm) and cannot fit a 65 mm HAT+. */}
        <footprint>
          {Array.from({ length: 20 }, (_, i) => {
            const x = -24.13 + i * 2.54;
            return [
              <platedhole
                key={`odd${i}`}
                shape="circle"
                holeDiameter="1.0mm"
                outerDiameter="1.8mm"
                pcbX={x}
                pcbY={HAT_HEADER.pitch / 2}
                portHints={[`pin${i * 2 + 1}`]}
              />,
              <platedhole
                key={`even${i}`}
                shape="circle"
                holeDiameter="1.0mm"
                outerDiameter="1.8mm"
                pcbX={x}
                pcbY={-HAT_HEADER.pitch / 2}
                portHints={[`pin${i * 2 + 2}`]}
              />,
            ];
          })}
        </footprint>
      </chip>
      {/* HAT+ mounting holes — locked mechanical objects, 2.75 mm, 3.5 mm from the
          board edges. Confirm against the current HAT+ mechanical drawing. */}
      <hole name="H1" diameter="2.75mm" pcbX={MOUNTING_HOLES[0].x} pcbY={MOUNTING_HOLES[0].y} />
      <hole name="H2" diameter="2.75mm" pcbX={MOUNTING_HOLES[1].x} pcbY={MOUNTING_HOLES[1].y} />
      <hole name="H3" diameter="2.75mm" pcbX={MOUNTING_HOLES[2].x} pcbY={MOUNTING_HOLES[2].y} />
      <hole name="H4" diameter="2.75mm" pcbX={MOUNTING_HOLES[3].x} pcbY={MOUNTING_HOLES[3].y} />
    </>
  );
}

/**
 * HAT+ ID EEPROM (CAT24C32-compatible, 0x50). docs/27 §8.
 * ID_SD/ID_SC are 3.9 kOhm pull-ups to PI_3V3; WP has a 1 kOhm pull-up plus a
 * test point. The ID bus is supplied from PI_3V3 and does not reach the ECP5.
 */
export function HatIdEeprom() {
  return (
    <>
      <chip
        name="U_EE"
        footprint="soic8"
        {...at("host_debug", "U_EE")}
        pinLabels={{
          pin1: "A0", pin2: "A1", pin3: "A2", pin4: "GND",
          pin5: "SDA", pin6: "SCL", pin7: "WP", pin8: "VCC",
        }}
        pinAttributes={{ VCC: { requiresPower: true }, GND: { requiresGround: true } }}
        connections={{ A0: GND, A1: GND, A2: GND, GND: GND, SDA: N.idSd, SCL: N.idSc, VCC: N.pi3v3 }}
      />
      <resistor name="REESD" resistance="3.9k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C51721"] }} {...at("host_debug", "REESD")}
        connections={{ pin1: N.pi3v3, pin2: N.idSd }} />
      <resistor name="REESC" resistance="3.9k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C51721"] }} {...at("host_debug", "REESC")}
        connections={{ pin1: N.pi3v3, pin2: N.idSc }} />
      <resistor name="REEWP" resistance="1k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C11702"] }} {...at("host_debug", "REEWP")}
        connections={{ pin1: N.pi3v3, pin2: ".U_EE > .WP" }} />
      <capacitor name="CEE1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("host_debug", "CEE1")}
        connections={{ pin1: N.pi3v3, pin2: GND }} />
    </>
  );
}
