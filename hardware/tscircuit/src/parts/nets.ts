/**
 * Net names for the Rev.0 HAT+ design.
 *
 * Rail nets are prefixed with `rail_` because a net selector must not begin with
 * a digit. The mapping to the documented rail names in power-plan.json is 1:1:
 *
 *   rail_PI_5V      <-> PI_5V
 *   rail_PI_3V3     <-> PI_3V3
 *   rail_5V_SYS     <-> 5V_SYS
 *   rail_5V_AFE     <-> 5V_AFE
 *   rail_3V3_D      <-> 3V3_D
 *   rail_3V3_ADC_A  <-> 3V3_ADC_A
 *   rail_3V3_CLK    <-> 3V3_CLK
 *   rail_2V5_AUX    <-> 2V5_AUX
 *   rail_1V1_CORE   <-> 1V1_CORE
 *
 * Functional nets keep their documented names unchanged.
 */
export const N = {
  gnd: "net.GND",

  pi5v: "net.rail_PI_5V",
  pi3v3: "net.rail_PI_3V3",
  v5sys: "net.rail_5V_SYS",
  v5afe: "net.rail_5V_AFE",
  v3v3d: "net.rail_3V3_D",
  v3v3adc: "net.rail_3V3_ADC_A",
  v3v3clk: "net.rail_3V3_CLK",
  v2v5aux: "net.rail_2V5_AUX",
  v1v1core: "net.rail_1V1_CORE",

  /** antenna / AFE */
  antIn: "net.ANT_IN",
  vcmAfe: "net.VCM_AFE",
  afeOut: "net.AFE_BUF_OUT",
  bpfIn: "net.BPF_IN",
  bpfOut: "net.BPF_OUT",
  pgaIn: "net.PGA_IN",
  pgaOut: "net.PGA_OUT",
  adcInP: "net.ADC_IN_P",
  adcInN: "net.ADC_IN_N",
  animp: "net.ADC_DRV_IN",
  vcmAdc: "net.ADC_VCM",
  adcRef: "net.ADC_REF",

  /** digital */
  clk25m: "net.CLK_25M",
  adcSck: "net.ADC_SCK",
  adcSdo: "net.ADC_SDO",
  adcConv: "net.ADC_CONV",
  pgaSck: "net.PGA_SCK",
  pgaMosi: "net.PGA_MOSI",
  pgaCsN: "net.PGA_CS_N",
  pgaSckF: "net.PGA_SCK_F",
  pgaMosiF: "net.PGA_MOSI_F",
  pgaCsF: "net.PGA_CS_F",

  ppsRef: "net.PPS_REF",
  lcdScl: "net.LCD_SCL",
  lcdSda: "net.LCD_SDA",
  lcdRstN: "net.LCD_RST_N",
  lcdBlEn: "net.LCD_BL_EN",
  lcdBlA: "net.LCD_BL_A",
  lcdBlK: "net.LCD_BL_K",
  lcdBlGate: "net.LCD_BL_GATE",

  flashCsN: "net.FLASH_CS_N",
  flashClk: "net.FLASH_CLK",
  flashMosi: "net.FLASH_MOSI",
  flashMiso: "net.FLASH_MISO",

  spiMosi: "net.HAT_SPI_MOSI",
  spiMiso: "net.HAT_SPI_MISO",
  spiSclk: "net.HAT_SPI_SCLK",
  spiCsN: "net.HAT_SPI_CS_N",
  irq: "net.HAT_IRQ",
  resetN: "net.HAT_RESET_N",
  hatPps: "net.HAT_PPS",
  uartTx: "net.HAT_UART_TX",
  uartRx: "net.HAT_UART_RX",

  spiMosiPi: "net.HAT_SPI_MOSI_PI",
  spiMisoPi: "net.HAT_SPI_MISO_PI",
  spiSclkPi: "net.HAT_SPI_SCLK_PI",
  spiCsPi: "net.HAT_SPI_CS_N_PI",
  irqPi: "net.HAT_IRQ_PI",
  resetPi: "net.HAT_RESET_N_PI",
  ppsPi: "net.HAT_PPS_PI",
  uartTxPi: "net.HAT_UART_TX_PI",
  uartRxPi: "net.HAT_UART_RX_PI",

  idSd: "net.ID_SD",
  idSc: "net.ID_SC",
  jtagTck: "net.JTAG_TCK",
  jtagTms: "net.JTAG_TMS",
  jtagTdi: "net.JTAG_TDI",
  jtagTdo: "net.JTAG_TDO",
} as const;
