# Buffering Patterns

## Overview

Choosing the right buffer type is the single largest factor in a streaming
design's area, timing, and functional correctness.  This guide describes the
buffer modules available in this library, when to use each one, and how to
size them correctly.

---

## Buffer Types at a Glance

| Module                   | Depth    | Ready path   | CDC | Latency   | Use when …                        |
|--------------------------|----------|--------------|-----|-----------|-----------------------------------|
| `stream_pipeline_stage`  | 1 beat   | Combinational| No  | 1 cycle   | Simple pipeline register          |
| `stream_register_slice`  | 2 beats  | Registered   | No  | 1–2 cycles| Timing closure on both paths      |
| `stream_skid_buffer`     | 2 beats  | Registered   | No  | 1–2 cycles| Minimal registered backpressure   |
| `stream_mailbox`         | 1 beat   | Registered   | No  | 1 cycle   | Single-entry handoff register     |
| `stream_elastic_buffer`  | N beats  | Registered   | No  | 1 cycle   | Burst absorption, decoupling      |
| `stream_fifo`            | N beats  | Registered   | No  | 1 cycle   | Burst absorption with status flags|
| `stream_async_fifo`      | N beats  | Registered   | Yes | ≥2 cycles | Clock domain crossing             |

---

## Register Slice (`stream_register_slice`)

### When to Use

Use a register slice any time you need to:

- **Break a long combinational timing path** on the data bus.
- **Break the backpressure (`ready`) path** — the primary advantage over a
  simple pipeline stage.
- Insert a pipeline stage in a high-frequency design where the ready signal
  propagates across many modules.

### How It Works

The register slice uses two internal slots.  Slot 0 is the primary output
register; slot 1 is the skid register.  When slot 0 is full and downstream is
not accepting, an incoming beat is held in slot 1 and `s_ready` is deasserted
one cycle early.  This ensures that **both** `s_ready` (backpressure) and
`m_valid` (forward data) are fully registered.

```
                 ┌────────────┐
 s_valid ───────►│            ├───► m_valid (registered)
 s_data  ───────►│  slot 0    ├───► m_data  (registered)
                 │  slot 1    │
 m_ready ───────►│  (skid)    ├───► s_ready (registered)
                 └────────────┘
```

### Instantiation

```systemverilog
stream_register_slice #(
    .DATA_WIDTH (32),
    .USER_WIDTH (1),
    .KEEP_WIDTH (4)    // DATA_WIDTH/8 for byte-granularity
) u_reg_slice (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (up_valid), .s_ready (up_ready),
    .s_data  (up_data),  .s_keep  (up_keep),
    .s_last  (up_last),  .s_user  (up_user),
    .m_valid (dn_valid), .m_ready (dn_ready),
    .m_data  (dn_data),  .m_keep  (dn_keep),
    .m_last  (dn_last),  .m_user  (dn_user)
);
```

---

## Skid Buffer (`stream_skid_buffer`)

### When to Use

The skid buffer is a lighter variant of the register slice.  It provides the
same two-entry elastic behaviour but with a slightly simplified implementation.
Use it when you need registered backpressure and area is tight.

### Comparison with Register Slice

Both break the combinational path in both directions.  The register slice
offers a more formally verified skid implementation with explicit slot naming.
For most designs, the two are interchangeable.

---

## Pipeline Stage (`stream_pipeline_stage`)

### When to Use

Use the pipeline stage when:

- You need to register the **data path only** (not the ready path).
- The ready signal propagation is short and does not close timing.
- You want minimal area overhead (one set of flip-flops, no skid register).

### Limitation

`s_ready` is combinational: `s_ready = m_ready | ~m_valid`.  This means the
ready signal passes straight through to the upstream module.  In a long
pipeline chain, this can create multi-cycle combinational timing paths.

```systemverilog
stream_pipeline_stage #(
    .DATA_WIDTH (8)
) u_pipe (
    .clk (clk), .rst_n (rst_n),
    .s_valid (up_valid), .s_ready (up_ready),
    .s_data  (up_data),  .s_keep  (up_keep),
    .s_last  (up_last),  .s_user  (up_user),
    .m_valid (dn_valid), .m_ready (dn_ready),
    .m_data  (dn_data),  .m_keep  (dn_keep),
    .m_last  (dn_last),  .m_user  (dn_user)
);
```

---

## Elastic Buffer (`stream_elastic_buffer`)

### When to Use

The elastic buffer is the go-to choice when you need to **decouple** two
modules that may produce and consume at different instantaneous rates.  Choose
it over a plain FIFO when you do not need detailed occupancy counts but do want
`almost_full` / `almost_empty` flags.

### Depth Sizing

The required depth depends on the maximum burst length that the upstream module
can produce without the downstream being ready:

```
depth ≥ max_upstream_burst_length + pipeline_latency_downstream
```

Always round up to the next power of two (required by the implementation).

A depth of 16 is adequate for simple inter-stage decoupling.  For bursting
interfaces (e.g., a DMA engine), use 64–256 entries.

### almost_full / almost_empty Flags

These flags fire at occupancy thresholds:

- `almost_full`:  occupancy ≥ DEPTH−1 (one entry away from full)
- `almost_empty`: occupancy ≤ 1       (one entry away from empty)

Use `almost_full` to throttle a source before the buffer actually becomes
full, avoiding dropped beats.  Use `almost_empty` to wake a consumer before
the buffer drains.

```systemverilog
stream_elastic_buffer #(
    .DATA_WIDTH (8),
    .DEPTH      (64)
) u_elastic (
    .clk          (clk),   .rst_n        (rst_n),
    .s_valid      (src_valid), .s_ready  (src_ready),
    .s_data       (src_data),  .s_keep   (src_keep),
    .s_last       (src_last),  .s_user   (src_user),
    .m_valid      (snk_valid), .m_ready  (snk_ready),
    .m_data       (snk_data),  .m_keep   (snk_keep),
    .m_last       (snk_last),  .m_user   (snk_user),
    .almost_full  (buf_almost_full),
    .almost_empty (buf_almost_empty)
);
```

---

## FIFO (`stream_fifo`)

### When to Use

Use `stream_fifo` instead of `stream_elastic_buffer` when you need:

- A precise **occupancy count** (e.g., for software status registers).
- All four status flags: `full`, `empty`, `almost_full`, `almost_empty`.
- Compatibility with designs that poll occupancy for flow control.

### DEPTH Must Be a Power of 2

Both `stream_fifo` and `stream_elastic_buffer` require `DEPTH` to be an exact
power of 2 to allow natural binary pointer wrap-around.  The simulation-time
`initial` block will `$fatal` if this constraint is violated.

```
DEPTH = 2   → 2 entries   (minimum)
DEPTH = 16  → 16 entries  (common default)
DEPTH = 256 → 256 entries (for large bursts)
```

### Status Flags

```systemverilog
stream_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (16)
) u_fifo (
    // ... stream ports ...
    .count        (fifo_count),      // [$clog2(DEPTH):0]
    .full         (fifo_full),
    .empty        (fifo_empty),
    .almost_full  (fifo_almost_full),
    .almost_empty (fifo_almost_empty)
);
```

The `count` output does **not** include the output register; add 1 if the
output register contains valid data for an exact occupancy.

---

## Asynchronous FIFO (`stream_async_fifo`)

Use `stream_async_fifo` **only** for clock domain crossing (CDC).  All other
buffering should use synchronous primitives.  See `docs/async_fifo_notes.md`
for full details.

---

## Ping-Pong Buffer (`stream_ping_pong_buffer`)

### When to Use

A ping-pong (double) buffer is useful when:

- A **producer fills a complete frame** while a **consumer reads the previous
  frame** simultaneously.
- You need zero-wait-state handoff of complete frames between processing stages.
- The producer and consumer cannot be active on the same frame simultaneously.

### Operation

Two memory banks alternate roles.  While bank A is being written (by the
producer stream), bank B is being read (by the consumer stream).  At the end
of a frame, the banks swap.  This provides continuous fill-and-drain operation
with no idle cycles between frames.

```
Cycle:    0───────N   N───────2N  2N───────3N
Bank A:   [WRITE ]    [READ  ]    [WRITE ]
Bank B:   [READ  ]    [WRITE ]    [READ  ]
```

### Common Applications

- Video frame buffering (fill one frame, scan out the previous).
- DMA buffer rotation (fill while DMA transfers the other half).
- Audio double-buffering for interrupt-driven playback.

---

## Line Buffer (`stream_line_buffer`)

### When to Use

The line buffer is designed for **row-parallel image processing** pipelines
where a filter kernel requires simultaneous access to multiple rows of an
image.  It stores N complete rows and presents them as parallel output streams.

### Operation

The input stream writes one pixel per beat.  After `LINE_LENGTH` beats, the
buffer advances to the next row.  Parallel output ports expose K consecutive
rows simultaneously, enabling computation of a K-tap vertical filter.

### Common Applications

- 3×3 or 5×5 convolution kernels in image processing.
- Vertical edge detection (requires two adjacent rows).
- Interlace-to-progressive conversion.

---

## Circular Buffer (`stream_circular_buffer`)

### When to Use

The circular buffer provides a **power-of-2 ring** that allows the consumer to
re-read data without requiring the producer to retransmit.  Use it when:

- You need look-back access (e.g., reading bytes already consumed).
- The consumer may re-read the same window multiple times.
- You need a sliding window over the input stream.

### Common Applications

- Compression history buffers (LZ77 look-behind window).
- Network retransmission buffers (hold data until ACK received).
- Correlation windows in DSP.

---

## Depth Sizing Guidelines Summary

| Scenario                                 | Recommended depth                  |
|------------------------------------------|------------------------------------|
| Register slice / skid                    | Fixed at 2 (built-in)              |
| Simple inter-stage decoupling            | 4–16                               |
| Single burst absorption                  | max_burst_length, rounded up to PoT|
| Rate-mismatched clock domains (CDC)      | ≥ 4× max burst length              |
| DMA/host-facing interface                | 64–256                             |
| Video line buffer                        | line_length × num_lines            |
