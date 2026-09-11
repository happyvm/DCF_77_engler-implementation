export default () => (
  <board width="60mm" height="40mm" layers={4}>
    <chip name="J1A" footprint="pinrow40_rows2_cols20" pcbX={0} pcbY={-10} />
    <chip name="J1B" footprint="pinrow40" pcbX={0} pcbY={0} />
    <chip
      name="J1C"
      pinLabels={Object.fromEntries(Array.from({ length: 4 }, (_, i) => [`pin${i + 1}`, `P${i + 1}`]))}
      pcbX={0}
      pcbY={12}
    >
      <footprint>
        <platedhole shape="circle" holeDiameter="1mm" outerDiameter="1.7mm" pcbX={-3.81} pcbY={0} portHints={["pin1"]} />
        <platedhole shape="circle" holeDiameter="1mm" outerDiameter="1.7mm" pcbX={-1.27} pcbY={0} portHints={["pin2"]} />
        <platedhole shape="circle" holeDiameter="1mm" outerDiameter="1.7mm" pcbX={1.27} pcbY={0} portHints={["pin3"]} />
        <platedhole shape="circle" holeDiameter="1mm" outerDiameter="1.7mm" pcbX={3.81} pcbY={0} portHints={["pin4"]} />
      </footprint>
    </chip>
  </board>
)
