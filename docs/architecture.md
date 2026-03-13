# Library Architecture

## Overview

`streaming-rtl` is a vendor-neutral, fully synthesizable library of AXI-Stream
compatible RTL modules written in SystemVerilog.  Every module targets FPGAs and
ASICs without proprietary IP dependencies.  The design philosophy centres on three
pillars:

1. **Vendor-neutral** – no tool-specific pragmas in the functional logic; only
   optional hints (`ram_style`) that degrade gracefully.
2. **Synthesizable** – only synthesizable SystemVerilog constructs are used in the
   RTL.  Simulation-only checks are guarded by `// synthesis translate_off`.
3. **Parametric** – data widths, depths, counts, and protocol widths are all
   parameters; the same module adapts to 8-bit byte streams and 512-bit AXI
   data buses.

---

## Directory Structure

```
streaming-rtl/
├── rtl/
│   ├── core/               # Fundamental building blocks
│   │   ├── stream_async_fifo.sv
│   │   ├── stream_elastic_buffer.sv
│   │   ├── stream_fifo.sv
│   │   ├── stream_mailbox.sv
│   │   ├── stream_pipeline_stage.sv
│   │   ├── stream_register_slice.sv
│   │   └── stream_skid_buffer.sv
│   ├── framing/            # Frame-aware processing
│   │   ├── stream_depacketizer.sv
│   │   ├── stream_frame_detector.sv
│   │   ├── stream_frame_length_counter.sv
│   │   ├── stream_header_inserter.sv
│   │   ├── stream_header_stripper.sv
│   │   ├── stream_last_inserter.sv
│   │   ├── stream_last_remover.sv
│   │   └── stream_packetizer.sv
│   ├── arbitration/        # Multi-port fan-out and fan-in
│   │   ├── stream_arbiter_fixed_priority.sv
│   │   ├── stream_arbiter_round_robin.sv
│   │   ├── stream_broadcast.sv
│   │   ├── stream_demux.sv
│   │   ├── stream_join.sv
│   │   ├── stream_merge.sv
│   │   └── stream_mux.sv
│   ├── adapters/           # Width and rate conversion
│   │   ├── stream_aligner.sv
│   │   ├── stream_backpressure_adapter.sv
│   │   ├── stream_delay_line.sv
│   │   ├── stream_downsizer.sv
│   │   ├── stream_rate_matcher.sv
│   │   ├── stream_retimer.sv
│   │   ├── stream_upsizer.sv
│   │   └── stream_width_adapter.sv
│   ├── buffers/            # Specialised storage patterns
│   │   ├── stream_circular_buffer.sv
│   │   ├── stream_line_buffer.sv
│   │   ├── stream_ping_pong_buffer.sv
│   │   └── stream_reorder_buffer.sv
│   └── utils/              # Monitoring and control
│       ├── stream_counter.sv
│       ├── stream_idle_detector.sv
│       ├── stream_perf_monitor.sv
│       ├── stream_pulse_on_frame.sv
│       └── stream_timeout_detector.sv
├── testbenches/            # Simulation testbenches
├── examples/               # Composition examples
└── docs/                   # This documentation
```

---

## Interface Conventions

All modules use a subset of AXI4-Stream:

| Signal    | Direction | Description                                    |
|-----------|-----------|------------------------------------------------|
| `clk`     | input     | Rising-edge clock                              |
| `rst_n`   | input     | Active-low **synchronous** reset               |
| `s_valid` | input     | Upstream presents valid data                   |
| `s_ready` | output    | Module accepts data (backpressure)             |
| `s_data`  | input     | Payload data `[DATA_WIDTH-1:0]`                |
| `s_keep`  | input     | Byte enables `[KEEP_WIDTH-1:0]`                |
| `s_last`  | input     | End-of-frame marker                            |
| `s_user`  | input     | Sideband metadata `[USER_WIDTH-1:0]`           |
| `m_valid` | output    | Module presents valid data                     |
| `m_ready` | input     | Downstream accepts data                        |
| `m_data`  | output    | Payload data `[DATA_WIDTH-1:0]`                |
| `m_keep`  | output    | Byte enables `[KEEP_WIDTH-1:0]`                |
| `m_last`  | output    | End-of-frame marker                            |
| `m_user`  | output    | Sideband metadata `[USER_WIDTH-1:0]`           |

Prefix convention: **`s_`** = slave (upstream input), **`m_`** = master
(downstream output).  Multi-port modules use packed arrays, for example
`s_valid[NUM_INPUTS-1:0]`.

### Default Parameter Values

| Parameter    | Default           | Notes                        |
|--------------|-------------------|------------------------------|
| `DATA_WIDTH` | `8`               | Bits per beat                |
| `USER_WIDTH` | `1`               | Sideband bits                |
| `KEEP_WIDTH` | `DATA_WIDTH / 8`  | Byte-enable bits             |

---

## Reset Conventions

- Reset is **active-low** (`rst_n = 0` asserts reset).
- Reset is **synchronous** – it is sampled on the rising edge of `clk`.
- All state registers clear to a defined value (zero or idle state).
- `stream_async_fifo` has separate resets for each clock domain (`s_rst_n`,
  `m_rst_n`).  Both domains must be held in reset simultaneously before
  de-asserting; see `docs/async_fifo_notes.md` for the correct sequence.

---

## Coding Standards

### Language Constructs

```systemverilog
// Registers use always_ff
always_ff @(posedge clk) begin
    if (!rst_n) reg_q <= '0;
    else        reg_q <= reg_d;
end

// Combinational logic uses always_comb
always_comb begin
    next_state = IDLE;
    case (state)
        IDLE: next_state = s_valid ? ACTIVE : IDLE;
    endcase
end
```

- **`always_ff`** for all clocked logic.
- **`always_comb`** for all combinational logic.
- **`logic`** type for all signals (never `reg` or `wire`).
- **`unique case`** for one-hot / fully-covered case statements.
- **`'0` / `'1`** fill literals for width-agnostic resets and enables.

### Naming

- All identifiers use **snake_case**.
- Module names are prefixed `stream_`.
- Internal signals are not prefixed; port signals use `s_` / `m_` prefixes.
- Parameters use `UPPER_SNAKE_CASE`.
- State machine types use a `_e` suffix (`typedef enum ... state_e`).

### File Layout

Each file contains exactly one module.  The file name matches the module name.
Every file starts with `\`default_nettype none` and ends with
`\`default_nettype wire` to prevent implicit net declarations.  A `\`timescale`
directive is included at the top of each file.

---

## Module Categories and Purposes

### Core

The fundamental buffering and pipelining primitives.  Use these first when you
need to break timing paths, add elastic capacity, or cross clock domains.

| Module                   | Purpose                                       |
|--------------------------|-----------------------------------------------|
| `stream_register_slice`  | Fully-registered data + backpressure path     |
| `stream_pipeline_stage`  | Registered data, combinational ready path     |
| `stream_skid_buffer`     | Minimal two-entry elastic element             |
| `stream_elastic_buffer`  | FIFO-backed elastic decoupling                |
| `stream_fifo`            | Synchronous FIFO with status flags            |
| `stream_async_fifo`      | Dual-clock FIFO for CDC                       |
| `stream_mailbox`         | Single-entry registered handshake buffer      |

### Framing

Modules that understand the `last` signal and operate on complete frames.

| Module                       | Purpose                                   |
|------------------------------|-------------------------------------------|
| `stream_header_stripper`     | Remove leading header beats per frame     |
| `stream_header_inserter`     | Prepend header beats to each frame        |
| `stream_packetizer`          | Accumulate beats into fixed-size packets  |
| `stream_depacketizer`        | Split fixed-size packets into beats       |
| `stream_last_inserter`       | Inject `last` after N beats               |
| `stream_last_remover`        | Strip `last` from interior frames         |
| `stream_frame_length_counter`| Count beats per frame                     |
| `stream_frame_detector`      | Detect SoF / EoF events                   |

### Arbitration

Multi-port routing, merging, and fan-out.

| Module                         | Purpose                                  |
|--------------------------------|------------------------------------------|
| `stream_arbiter_round_robin`   | N:1 frame-locked round-robin arbiter     |
| `stream_arbiter_fixed_priority`| N:1 fixed-priority arbiter               |
| `stream_mux`                   | N:1 combinational mux (select signal)    |
| `stream_demux`                 | 1:N combinational demux                  |
| `stream_broadcast`             | 1:N fan-out with done-mask tracking      |
| `stream_merge`                 | N:1 permissive merge (first valid wins)  |
| `stream_join`                  | N:1 synchronising join (all-valid gate)  |

### Adapters

Width and rate conversion.

| Module                        | Purpose                                   |
|-------------------------------|-------------------------------------------|
| `stream_upsizer`              | Narrow → wide width conversion            |
| `stream_downsizer`            | Wide → narrow width conversion            |
| `stream_width_adapter`        | General-purpose width ratio conversion    |
| `stream_rate_matcher`         | Rate matching with elastic buffering      |
| `stream_retimer`              | Re-register for timing closure            |
| `stream_aligner`              | Align stream to word boundaries           |
| `stream_delay_line`           | Fixed-latency delay pipeline              |
| `stream_backpressure_adapter` | Convert between credit and ready/valid    |

### Buffers

Specialised storage patterns.

| Module                   | Purpose                                       |
|--------------------------|-----------------------------------------------|
| `stream_ping_pong_buffer`| Double-buffered capture/replay                |
| `stream_line_buffer`     | Row-based image line buffering                |
| `stream_circular_buffer` | Power-of-2 wrap-around storage                |
| `stream_reorder_buffer`  | Out-of-order resequencing                     |

### Utils

Non-intrusive monitoring and control.

| Module                    | Purpose                                      |
|---------------------------|----------------------------------------------|
| `stream_perf_monitor`     | Beat/byte/cycle/idle/backpressure counters   |
| `stream_counter`          | General-purpose event counter                |
| `stream_idle_detector`    | Assert flag after N idle cycles              |
| `stream_timeout_detector` | Assert flag after N cycles without transfer  |
| `stream_pulse_on_frame`   | Generate one pulse per frame                 |

---

## Composing Modules

Modules connect by wiring the `m_` outputs of one instance to the `s_` inputs
of the next.  The connection is always:

```
producer.m_valid → consumer.s_valid
producer.m_data  → consumer.s_data
producer.m_keep  → consumer.s_keep
producer.m_last  → consumer.s_last
producer.m_user  → consumer.s_user
consumer.s_ready → producer.m_ready   ← backpressure flows upstream
```

### Example: two-stage pipeline

```systemverilog
// Internal connection wires
logic                  pipe_valid, pipe_ready;
logic [DATA_WIDTH-1:0] pipe_data;
logic                  pipe_keep, pipe_last, pipe_user;

stream_register_slice #(.DATA_WIDTH(DATA_WIDTH)) u_stage1 (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (in_valid), .s_ready (in_ready),
    .s_data  (in_data),  .s_keep  (in_keep),
    .s_last  (in_last),  .s_user  (in_user),
    .m_valid (pipe_valid), .m_ready (pipe_ready),
    .m_data  (pipe_data),  .m_keep  (pipe_keep),
    .m_last  (pipe_last),  .m_user  (pipe_user)
);

stream_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(16)) u_stage2 (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (pipe_valid), .s_ready (pipe_ready),
    .s_data  (pipe_data),  .s_keep  (pipe_keep),
    .s_last  (pipe_last),  .s_user  (pipe_user),
    .m_valid (out_valid),  .m_ready (out_ready),
    .m_data  (out_data),   .m_keep  (out_keep),
    .m_last  (out_last),   .m_user  (out_user),
    // unused status ports
    .count(), .full(), .empty(), .almost_full(), .almost_empty()
);
```

See the `examples/` directory for complete, elaboration-ready composition
examples covering pipelines, packet processing, arbitration, CDC, and
broadcast/join topologies.
