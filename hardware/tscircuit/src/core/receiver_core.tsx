/**
 * DCF77 Engeler Rev.0 receiver core — composition of the analog front end, the
 * ADC boundary, the ECP5 subsystem, the reference clock, the PPS interface and
 * the local display.
 *
 * Signal chain (docs/11 §Target signal chain, updated by docs/20 / 21 / 22):
 *   ferrite -> OPA810 -> LTC1562 -> LTC6912 -> OPA2835 -> LTC1407A-1 -> ECP5
 */
import { AntennaInputCluster, BandPassFilter, ProgrammableGain } from "./afe";
import { AdcBoundary } from "./adc";
import { Ecp5AndConfiguration } from "./ecp5";
import { ReferenceClock } from "./clock";
import { PpsInterface } from "./pps";
import { LocalDisplay } from "./display";

export function ReceiverCore() {
  return (
    <>
      <ReceiverAnalogPath />
      <AdcBoundary />
      <Ecp5AndConfiguration />
      <ReferenceClock />
      <PpsInterface />
      <LocalDisplay />
    </>
  );
}

export function ReceiverAnalogPath() {
  return (
    <>
      <AntennaInputCluster />
      <BandPassFilter />
      <ProgrammableGain />
    </>
  );
}
