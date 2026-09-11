# DSP Decision 09 — Memory organisation

## Status
Resolved. The time-decoding memory is organised as a synchronous circular buffer
(`soft_history`) of 3 600 entries, each holding one second of AM and PM soft
evidence plus metadata.

## Context
The ML decoder needs access to the last minute (60 seconds) of AM evidence for
field extraction, and the telemetry system may need up to one hour (3 600
seconds) of history for diagnostics. Rather than multiple separate memories, a
single circular buffer shared between a writer (the evidence aggregator) and
readers (the field sequencer, future telemetry scanner) reduces BRAM cost.

## Decision

### soft_history structure
| Depth | 3600 entries (one hour of seconds) |
|---|---|
| Write pointer | `history_wp` (HIST_AW bits, wraps at HISTORY_DEPTH) |
| AM evidence | 16-bit signed per entry |
| PM evidence | 16-bit signed per entry |
| Sample valid | 1 bit (1 = this second had valid AM and PM) |
| Quality | 8-bit (phase measurement quality 0-255) |
| Second position | 6-bit (0-59 within the minute) |
| Total per entry | 47 bits |

### Read/write arbitration
- **Writer**: `second_evidence_aggregator` writes one entry per second after
  both AM and PM evidence are available.
- **Primary reader**: `ml_field_sequencer` walks the last 60 entries newest-
  to-oldest once per minute (triggered by `frame_start`). It owns the read port
  outright during its scan.
- **The `ml_decoder_controller`** has its own scan interface but it is currently
  unused (tied off to `1'b0`); the field sequencer is the sole reader.

### Memory inference
The `soft_history` module uses a simple packed array with synchronous read:
```systemverilog
reg [EVIDENCE_BITS-1:0] am_mem [0:DEPTH-1];
```

This is intentionally portable RTL with no vendor primitives. Yosys infers EBR
(DP16KD) on ECP5 for this pattern. With 3 600 × 47 bits, the memory requires:
- 169 200 bits total
- ~4 DP16KD blocks (4 × 18 432 bits = 73 728 bits each, configurable as
  2048×9 or 1024×18)
- At 3600 entries of 47 bits each, Yosys typically infers a configuration using
  5 DP16KD blocks

This is well within the 32 EBR18 budget (XC3S1400AN envelope).

### Second-number alignment
`pm_minute_sync` reports the search position at which the minute marker's
15-second window ended (DCF77 second 14 when aligned). The core derives
`second_number` from this, realigning the counter only on qualified markers
confirmed by two consecutive consistent results. This prevents a single damaged
marker from shifting every history record by one second.

### Evidence duality
Each second carries both AM and PM evidence so the ML decoder can use either or
both. Currently only AM evidence is used for time decoding (the PM correlation
is for minute sync only). Future cross-validation between AM and PM decode
results can be implemented without changing the memory organisation.

## References
- `rtl/ml_decoder/soft_history.sv` — synchronous circular buffer
- `rtl/ml_decoder/second_evidence_aggregator.sv` — per-second record assembly
- `rtl/core/dcf77_receiver_core.sv` — write/read arbitration and second numbering
- `rtl/ml_decoder/ml_field_sequencer.sv` — sole reader, 60-entry scan
- `rtl/resource_budget.json` — 32 EBR18 limit