/**
 * Raspberry Pi host interface: SPI, UART, IRQ, reset and PPS copy.
 *
 * docs/27 §7: all host-interface balls are in ECP5 bank 1 powered by 3V3_D, so no
 * level shifter is required. ~33 ohm source-series damping is applied on the SPI
 * clock/data outputs and on PPS/IRQ where practical, the UART lines get 33 ohm
 * series resistors plus 47 kOhm idle-high pull-ups, and HAT_RESET_N gets a
 * 10 kOhm pull-up to PI_3V3.
 *
 * UART is a low-rate 115200 8N1 date/time/status path transmitted once per second
 * in the ~993...999 ms tail after the DCF77 PM sequence (docs/29).
 */
import { N } from "../parts/nets";
import { at } from "../parts";
import { FP0402_RES, FP0402_CAP } from "../parts/footprints";

const GND = N.gnd;

export function RaspberryPiSpi() {
  return (
    <>
      {/* SPI0: Pi master -> ECP5 slave */}
      <resistor name="RS_SPI_SCLK" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_SPI_SCLK")}
        connections={{ pin1: N.spiSclkPi, pin2: N.spiSclk }} />
      <resistor name="RS_SPI_MOSI" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_SPI_MOSI")}
        connections={{ pin1: N.spiMosiPi, pin2: N.spiMosi }} />
      <resistor name="RS_SPI_MISO" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_SPI_MISO")}
        connections={{ pin1: N.spiMiso, pin2: N.spiMisoPi }} />
      <resistor name="RS_SPI_CS" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_SPI_CS")}
        connections={{ pin1: N.spiCsPi, pin2: N.spiCsN }} />

      {/* IRQ / data-ready, active state defined in the FPGA */}
      <resistor name="RIRQ" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RIRQ")}
        connections={{ pin1: N.irq, pin2: N.irqPi }} />

      {/* reset: 10 kOhm pull-up to PI_3V3 (open-drain host reset only) */}
      <resistor name="RRST" resistance="10k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25744"] }} {...at("host_debug", "RRST")}
        connections={{ pin1: N.resetN, pin2: N.pi3v3 }} />

      {/* PPS copy to the Pi GPIO; defined low until the timebase is valid */}
      <resistor name="RTPS_UP" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RTPS_UP")}
        connections={{ pin1: N.hatPps, pin2: N.ppsPi }} />
      <resistor name="RTPS_DN" resistance="100k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25741"] }} {...at("host_debug", "RTPS_DN")}
        connections={{ pin1: N.ppsPi, pin2: GND }} />

      {/* UART: 33 ohm series + 47 kOhm idle-high pull-ups on the 3V3_D domain */}
      <resistor name="RS_UART_TX" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_UART_TX")}
        connections={{ pin1: N.uartTx, pin2: N.uartTxPi }} />
      <resistor name="RS_UART_RX" resistance="33" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25105"] }} {...at("host_debug", "RS_UART_RX")}
        connections={{ pin1: N.uartRxPi, pin2: N.uartRx }} />
      <resistor name="RUART_TX" resistance="47k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25792"] }} {...at("host_debug", "RUART_TX")}
        connections={{ pin1: N.v3v3d, pin2: N.uartTx }} />
      <resistor name="RUART_RX" resistance="47k" footprint={FP0402_RES} supplierPartNumbers={{ jlcpcb: ["C25792"] }} {...at("host_debug", "RUART_RX")}
        connections={{ pin1: N.v3v3d, pin2: N.uartRx }} />

      {/* local host-interface decoupling */}
      <capacitor name="CVD1" capacitance="100nF" footprint={FP0402_CAP} supplierPartNumbers={{ jlcpcb: ["C1525"] }} {...at("host_debug", "CVD1")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="CVD2" capacitance="1uF" footprint="0603" {...at("host_debug", "CVD2")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
      <capacitor name="CVD3" capacitance="10uF" footprint="0805" {...at("host_debug", "CVD3")}
        connections={{ pin1: N.v3v3d, pin2: GND }} />
    </>
  );
}
