# streaming-rtl

A **high-quality, open-source SystemVerilog library** of reusable streaming data-path and flow-control components for FPGA and ASIC designs.

The library provides **35 fully parameterized, vendor-neutral, synthesizable modules** organized around a consistent **ready/valid (AXI4-Stream compatible) handshake interface**.

---

## Features

- **Clean, synthesizable RTL** — `always_ff`/`always_comb` only, no latches, no vendor IP
- **Vendor-neutral** — works with Xilinx, Intel/Altera, Lattice, any ASIC flow
- **Fully parameterized** — `DATA_WIDTH`, `DEPTH`, `USER_WIDTH`, `KEEP_WIDTH`, and more
- **Consistent interface** — ready/valid with optional `last`, `keep`, `user` sideband signals
- **Active-low synchronous reset** (`rst_n`) throughout
- **Documented** — every module has a file-header comment covering latency, throughput, backpressure, and limitations

---

## Repository Layout

```
streaming-rtl/
├── rtl/
│   ├── core/          # Register slices, FIFOs, skid buffers
│   ├── buffers/       # Line, circular, reorder, ping-pong buffers
│   ├── framing/       # Packet framing and header utilities
│   ├── arbitration/   # Arbiters, mux, demux, broadcast, join
│   ├── adapters/      # Width adapters, upsizers, downsizers, CDC
│   └── utils/         # Counters, monitors, detectors
├── testbenches/       # SystemVerilog testbench for every module
├── examples/          # Example top-level designs
├── docs/              # Architecture and design guides
├── scripts/           # Helper scripts
└── README.md
```

---

## Interface Convention

All modules use the same ready/valid streaming interface:

```
Slave (input) side:         Master (output) side:
  s_valid                     m_valid
  s_ready  ← backpressure     m_ready  ← backpressure
  s_data                      m_data
  s_keep                      m_keep
  s_last                      m_last
  s_user                      m_user
```

A **transfer occurs** when both `valid` and `ready` are high on the same rising clock edge.
The `last` signal marks the final beat of a frame/packet.

See [`docs/ready_valid_basics.md`](docs/ready_valid_basics.md) for details.

---

## Module Reference

### Core Streaming Primitives (`rtl/core/`)

| Module | Description | Latency |
|--------|-------------|---------|
| [`stream_register_slice`](rtl/core/stream_register_slice.sv) | Fully registered cut (both data and ready paths) | 1–2 cycles |
| [`stream_pipeline_stage`](rtl/core/stream_pipeline_stage.sv) | Single register stage; combinational ready path | 1 cycle |
| [`stream_skid_buffer`](rtl/core/stream_skid_buffer.sv) | 2-entry skid buffer; registered s_ready | 1 cycle |
| [`stream_elastic_buffer`](rtl/core/stream_elastic_buffer.sv) | FIFO-backed elastic buffer with almost_full/empty | 1 cycle |
| [`stream_mailbox`](rtl/core/stream_mailbox.sv) | Single-entry write-when-empty / read-when-full | 1 cycle |
| [`stream_fifo`](rtl/core/stream_fifo.sv) | Synchronous FIFO; count/full/empty/almost_* flags | 1 cycle |
| [`stream_async_fifo`](rtl/core/stream_async_fifo.sv) | Dual-clock FIFO with Gray-code pointer CDC | SYNC_STAGES+2 |

### Framing and Packet Primitives (`rtl/framing/`)

| Module | Description |
|--------|-------------|
| [`stream_packetizer`](rtl/framing/stream_packetizer.sv) | Inserts `last` every `PACKET_LEN` beats |
| [`stream_depacketizer`](rtl/framing/stream_depacketizer.sv) | Strips `last`; outputs continuous stream + frame count |
| [`stream_frame_length_counter`](rtl/framing/stream_frame_length_counter.sv) | Counts beats per frame; outputs count on `last` |
| [`stream_frame_detector`](rtl/framing/stream_frame_detector.sv) | Generates `sof` and `eof` pulses |
| [`stream_last_inserter`](rtl/framing/stream_last_inserter.sv) | Inserts `last` every N beats or on sideband signal |
| [`stream_last_remover`](rtl/framing/stream_last_remover.sv) | Strips `last`; output `m_last` is always 0 |
| [`stream_header_inserter`](rtl/framing/stream_header_inserter.sv) | Prepends a fixed header to each frame |
| [`stream_header_stripper`](rtl/framing/stream_header_stripper.sv) | Strips first N beats as header; exposes captured header |

### Arbitration and Sharing (`rtl/arbitration/`)

| Module | Description |
|--------|-------------|
| [`stream_arbiter_fixed_priority`](rtl/arbitration/stream_arbiter_fixed_priority.sv) | N-input fixed-priority arbiter (input 0 = highest); frame-locked |
| [`stream_arbiter_round_robin`](rtl/arbitration/stream_arbiter_round_robin.sv) | N-input round-robin arbiter; frame-locked |
| [`stream_mux`](rtl/arbitration/stream_mux.sv) | N:1 combinational mux with external `sel` |
| [`stream_demux`](rtl/arbitration/stream_demux.sv) | 1:N combinational demux with external `sel` |
| [`stream_broadcast`](rtl/arbitration/stream_broadcast.sv) | 1:N broadcaster; per-output done-mask |
| [`stream_merge`](rtl/arbitration/stream_merge.sv) | N:1 sequential frame merge |
| [`stream_join`](rtl/arbitration/stream_join.sv) | N-input synchronizer; fires when all inputs valid |

### Adapters and Alignment (`rtl/adapters/`)

| Module | Description |
|--------|-------------|
| [`stream_upsizer`](rtl/adapters/stream_upsizer.sv) | Combines RATIO narrow beats → 1 wide beat |
| [`stream_downsizer`](rtl/adapters/stream_downsizer.sv) | Splits 1 wide beat → RATIO narrow beats |
| [`stream_width_adapter`](rtl/adapters/stream_width_adapter.sv) | Generic width adapter (up or down via `generate`) |
| [`stream_aligner`](rtl/adapters/stream_aligner.sv) | Byte-aligns stream by packing valid bytes (keep-aware) |
| [`stream_delay_line`](rtl/adapters/stream_delay_line.sv) | FIFO-based stream delay by N cycles |
| [`stream_rate_matcher`](rtl/adapters/stream_rate_matcher.sv) | CDC rate adapter using an inline async FIFO |
| [`stream_retimer`](rtl/adapters/stream_retimer.sv) | Single pipeline register for timing closure |
| [`stream_backpressure_adapter`](rtl/adapters/stream_backpressure_adapter.sv) | FIFO buffer in ABSORB or DROP mode |

### Buffering and Reordering (`rtl/buffers/`)

| Module | Description |
|--------|-------------|
| [`stream_line_buffer`](rtl/buffers/stream_line_buffer.sv) | Ping-pong line buffer; `line_ready` flag |
| [`stream_circular_buffer`](rtl/buffers/stream_circular_buffer.sv) | Ring buffer with exposed count/full/empty |
| [`stream_reorder_buffer`](rtl/buffers/stream_reorder_buffer.sv) | Out-of-order reorder buffer using sequence IDs |
| [`stream_ping_pong_buffer`](rtl/buffers/stream_ping_pong_buffer.sv) | Double buffer; `swap` pulse on bank switch |

### Utility Modules (`rtl/utils/`)

| Module | Description |
|--------|-------------|
| [`stream_counter`](rtl/utils/stream_counter.sv) | Counts beats or frames; `count_clear` input |
| [`stream_perf_monitor`](rtl/utils/stream_perf_monitor.sv) | Beat/byte/cycle/idle/back-pressure counters |
| [`stream_idle_detector`](rtl/utils/stream_idle_detector.sv) | Asserts `idle` after N consecutive idle cycles |
| [`stream_pulse_on_frame`](rtl/utils/stream_pulse_on_frame.sv) | Single-cycle pulse on SoF or EoF |
| [`stream_timeout_detector`](rtl/utils/stream_timeout_detector.sv) | Detects partial frames exceeding a timeout |

---

## Quick Start

### Instantiating a FIFO

```systemverilog
stream_fifo #(
    .DATA_WIDTH (32),
    .DEPTH      (64),
    .USER_WIDTH (1),
    .KEEP_WIDTH (4)
) u_fifo (
    .clk         (clk),
    .rst_n       (rst_n),
    .s_valid     (src_valid),
    .s_ready     (src_ready),
    .s_data      (src_data),
    .s_keep      (src_keep),
    .s_last      (src_last),
    .s_user      (src_user),
    .m_valid     (dst_valid),
    .m_ready     (dst_ready),
    .m_data      (dst_data),
    .m_keep      (dst_keep),
    .m_last      (dst_last),
    .m_user      (dst_user),
    .count       (fifo_count),
    .full        (fifo_full),
    .empty       (fifo_empty),
    .almost_full (),
    .almost_empty()
);
```

### Chaining Modules

```systemverilog
// Register slice → FIFO — internal wires
wire rs_valid, rs_ready;
wire [7:0] rs_data;
wire rs_keep, rs_last, rs_user;

stream_register_slice #(.DATA_WIDTH(8)) u_rs (
    .clk(clk), .rst_n(rst_n),
    .s_valid(src_valid), .s_ready(src_ready),
    .s_data(src_data), .s_keep(src_keep),
    .s_last(src_last), .s_user(src_user),
    .m_valid(rs_valid), .m_ready(rs_ready),
    .m_data(rs_data), .m_keep(rs_keep),
    .m_last(rs_last), .m_user(rs_user)
);

stream_fifo #(.DATA_WIDTH(8), .DEPTH(16)) u_fifo (
    .clk(clk), .rst_n(rst_n),
    .s_valid(rs_valid), .s_ready(rs_ready),
    .s_data(rs_data), .s_keep(rs_keep),
    .s_last(rs_last), .s_user(rs_user),
    .m_valid(dst_valid), .m_ready(dst_ready),
    .m_data(dst_data), .m_keep(dst_keep),
    .m_last(dst_last), .m_user(dst_user),
    .count(), .full(), .empty(), .almost_full(), .almost_empty()
);
```

---

## Examples

| Example | Description | Modules Used |
|---------|-------------|--------------|
| [`ex1_streaming_pipeline.sv`](examples/ex1_streaming_pipeline.sv) | Register slice → FIFO → perf monitor | core |
| [`ex2_packet_processing.sv`](examples/ex2_packet_processing.sv) | Header strip → pipeline → header reinsert | framing |
| [`ex3_multi_source_arbitration.sv`](examples/ex3_multi_source_arbitration.sv) | 4 sources → round-robin → elastic buffer | arbitration |
| [`ex4_dual_clock_system.sv`](examples/ex4_dual_clock_system.sv) | Fast domain → async FIFO → slow domain | core/adapters |
| [`ex5_broadcast_join.sv`](examples/ex5_broadcast_join.sv) | Broadcast → dual processing paths → join | arbitration |

---

## Documentation

| Document | Description |
|----------|-------------|
| [`docs/architecture.md`](docs/architecture.md) | Library structure, conventions, coding rules |
| [`docs/ready_valid_basics.md`](docs/ready_valid_basics.md) | Handshake timing, rules, ASCII diagrams |
| [`docs/buffering_patterns.md`](docs/buffering_patterns.md) | Buffer type selection and depth sizing |
| [`docs/arbitration_patterns.md`](docs/arbitration_patterns.md) | Arbiter tradeoffs, broadcast, merge vs join |
| [`docs/packet_streaming.md`](docs/packet_streaming.md) | Frame structure, header workflows, timeouts |
| [`docs/async_fifo_notes.md`](docs/async_fifo_notes.md) | Gray code CDC, reset sequences, pitfalls |

---

## Coding Conventions

| Item | Convention |
|------|-----------|
| Language | SystemVerilog (IEEE 1800-2012) |
| Sequential logic | `always_ff @(posedge clk)` |
| Combinational logic | `always_comb` |
| Signal type | `logic` (no `reg`/`wire` distinction) |
| Reset | Active-low synchronous (`rst_n`) |
| Module names | `snake_case` |
| Parameters | `UPPER_CASE` |
| Signals | `snake_case` |
| Clock | `clk` (write side: `s_clk`, read side: `m_clk`) |

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 Kevin Coleman
