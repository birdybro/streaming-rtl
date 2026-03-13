# Packet and Frame Streaming

## Overview

Many streaming protocols transport data as discrete **frames** (also called
packets): bounded sequences of beats that begin at a start-of-frame (SoF) and
end at an end-of-frame (EoF) beat marked by `last=1`.  This document explains
the frame model used by this library's framing modules, and describes the
correct workflows for header manipulation, frame length counting, idle and
timeout detection, and rate matching for packet streams.

---

## Frame Structure

A frame consists of one or more consecutive beats on a ready/valid stream.
The final beat of the frame carries `last=1`.  Interior beats have `last=0`.
There is no explicit SoF signal; the beat following the previous EoF is
implicitly the new SoF.

```
clk    ___╱‾╲___╱‾╲___╱‾╲___╱‾╲___╱‾╲___╱‾╲___╱‾╲___
valid  _________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲_____________
ready  _________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲_____________
data   ----------[ H0 ][ H1 ][ D0 ][ D1 ][ D2 ]-------
last   __________________________________╱‾‾‾‾╲_______
                  ←── header ──►←────── payload ──────►
                  SoF                              EoF
```

**Rules:**
- Every frame must end with exactly one `last=1` beat.
- A single-beat frame is valid (SoF == EoF: `last=1` on the first beat).
- Stalls (valid=0 or ready=0) may occur at any point within a frame; the
  frame is simply extended until the stall resolves.
- A frame must not span a gap where `valid` goes low without `last` having
  been seen; that would be a protocol violation.

### `keep` in the Final Beat

The `keep` signal indicates which bytes in a beat contain valid data.  For
all but the last beat, `keep` is typically all-ones.  The last beat may have
trailing bytes disabled to signal a partial beat:

```
// DATA_WIDTH=32 (4 bytes), frame payload is 10 bytes:
// Beats 0 and 1 carry 4 bytes each (keep = 4'b1111)
// Beat 2 carries 2 bytes (keep = 4'b0011, last = 1)
```

---

## Packetizer and Depacketizer

### `stream_packetizer`

Accumulates incoming beats into fixed-size packets of `PACKET_BEATS` beats.
When the accumulator is full, `last` is inserted automatically.  Incoming
`last` signals from the source are respected: a frame shorter than
`PACKET_BEATS` will be emitted immediately with `last` from the source.

**Use when:**
- A variable-length stream must be segmented into fixed-size units for a
  downstream protocol (e.g., splitting an Ethernet payload into ATM cells or
  USB packets).
- You want to enforce a maximum frame size.

### `stream_depacketizer`

The inverse: strips the `last` that was inserted by the packetizer (or any
other framing mechanism) and passes the payload beats as a flat stream.
Optionally re-asserts `last` only on the original end-of-message boundary
(if tracked via `user` sideband).

**Use when:**
- Unpacking fixed-size protocol units back into a continuous payload stream.
- Removing intermediate framing added for transport.

---

## Header Insertion and Stripping

A common pattern is to strip a protocol header at ingress, process the
payload, then reattach the (possibly modified) header at egress.

### `stream_header_stripper`

Absorbs the first `HEADER_BEATS` beats of each frame and exposes them on a
sideband `hdr_data` / `hdr_valid` port.  After the header is captured,
payload beats flow transparently to the master port.

```
Incoming frame:   [ H0 ][ H1 ][ H2 ][ H3 ][ D0 ][ D1 ][ D2 ]
                  └───── header (HEADER_BEATS=4) ──────┘└─── payload ────┘

Master output:                                    [ D0 ][ D1 ][ D2 ]
hdr_valid pulse:                           ─╱‾╲─ (one cycle after H3 accepted)
hdr_data:                                  [H0|H1|H2|H3] (stable until next frame)
```

`hdr_valid` pulses exactly **once per frame** for one clock cycle, the cycle
after the last header beat is accepted.  `hdr_data` is
`HEADER_BEATS * DATA_WIDTH` bits wide and is stable from `hdr_valid` until
the end of the payload (`s_last` accepted).

Truncated frames (fewer than `HEADER_BEATS` beats before `last`) do **not**
produce a `hdr_valid` pulse.

### `stream_header_inserter`

Waits for a `hdr_valid` / `hdr_ready` handshake on the sideband port, latches
`hdr_data`, then outputs `HEADER_BEATS` header beats followed by the payload
stream transparently.

```systemverilog
// Loopback: stripped header fed directly back to inserter
stream_header_stripper #(.DATA_WIDTH(8), .HEADER_BEATS(4)) u_strip (
    // ... stream ports ...
    .hdr_data  (hdr_data),
    .hdr_valid (hdr_valid)
);

stream_header_inserter #(.DATA_WIDTH(8), .HEADER_BEATS(4)) u_insert (
    // ... stream ports ...
    .hdr_valid (hdr_valid),
    .hdr_ready (hdr_ready),    // consumed by inserter
    .hdr_data  (hdr_data)
);
```

**Important:** The `hdr_valid` / `hdr_ready` handshake between the stripper
and inserter is a standard ready/valid pair.  The inserter asserts `hdr_ready`
during its `S_HDR_WAIT` state.  The stripper's `hdr_valid` is a one-cycle
pulse; the inserter must be in `S_HDR_WAIT` when this pulse arrives.  For
back-to-back frames this is guaranteed because the inserter returns to
`S_HDR_WAIT` on the accepted `s_last` beat, and the stripper produces its next
`hdr_valid` at least `HEADER_BEATS` cycles later.

### Header Rewrite Workflow

To modify the header between strip and insert:

```
source ──► stream_header_stripper ──[hdr_data]──► header_rewrite_logic ──[hdr_data']──► stream_header_inserter
                │ (payload)                                                                      │
                ▼                                                                                │
         stream_register_slice (or FIFO) ─────────────────────────────────────────────────────►─┘
```

The `hdr_data` bus from the stripper feeds user logic that computes a modified
`hdr_data'`.  The modified header must be valid when the inserter expects its
`hdr_valid`.  If the rewrite logic adds latency, buffer the payload path with
a FIFO deep enough to absorb the header-rewrite latency.

---

## Frame Length Counter

`stream_frame_length_counter` counts the number of accepted beats per frame.
The count is presented on a `length` output and a `length_valid` pulse fires
on the cycle the EoF beat is accepted.

**Use when:**
- Protocol headers must carry a byte count or beat count for the payload.
- You need to detect unexpectedly short or long frames.

```systemverilog
stream_frame_length_counter #(
    .DATA_WIDTH   (8),
    .LENGTH_WIDTH (16)
) u_len_cnt (
    .clk          (clk),   .rst_n        (rst_n),
    .s_valid      (s_valid), .s_ready    (s_ready),
    .s_data       (s_data),  .s_keep     (s_keep),
    .s_last       (s_last),  .s_user     (s_user),
    .m_valid      (m_valid), .m_ready    (m_ready),
    .m_data       (m_data),  .m_keep     (m_keep),
    .m_last       (m_last),  .m_user     (m_user),
    .length       (frame_length),
    .length_valid (frame_length_valid)
);
```

---

## Timeout Detection

`stream_timeout_detector` monitors a stream and asserts `timeout` after
`TIMEOUT_CYCLES` clock cycles elapse without a transfer.  This is useful for
detecting:

- A source that stalls mid-frame (broken producer).
- An idle link that should be sending keepalive frames.
- A DMA channel that has stopped unexpectedly.

```systemverilog
stream_timeout_detector #(
    .TIMEOUT_CYCLES (1000)
) u_timeout (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (s_valid), .s_ready (s_ready),
    // pass-through ports ...
    .timeout (link_timeout_flag)
);
```

The `timeout` flag asserts one cycle after the timer expires and remains high
until a transfer occurs or the module is reset.

---

## Idle Detection

`stream_idle_detector` asserts `idle` after the stream has been idle
(`valid=0`) for `IDLE_CYCLES` consecutive cycles.  It de-asserts `idle`
immediately when `valid` is re-asserted.

**Use when:**
- You need to power-gate or clock-gate downstream logic when the stream is
  inactive.
- An upstream source must be notified to generate keepalive traffic.

Difference from timeout: `stream_timeout_detector` measures time since the
**last accepted transfer** (valid & ready); `stream_idle_detector` measures
time since `valid` was last high.

---

## Rate Matching for Packet Streams

When a producer and consumer have different average throughput rates (e.g., a
100 Mb/s input and a 1 Gb/s output), `stream_rate_matcher` adjusts the output
rate by inserting or absorbing idle cycles between beats.

### `stream_async_fifo` for Rate Matching Across Clock Domains

If the rate difference arises because the two sides use different clocks, use
`stream_async_fifo` rather than a synchronous rate matcher.  The async FIFO
naturally absorbs the rate mismatch as long as the long-term average throughput
of the write side does not exceed the read side's consumption rate.

### Burst Mode vs Continuous Mode

Most packetised protocols transmit in bursts: a frame arrives fully, then the
link is idle until the next frame.  The FIFO must be deep enough to hold at
least one full worst-case frame:

```
min_depth = max_frame_beats + 1   (rounded up to next power of 2)
```

For continuous back-to-back frames with no inter-frame gap, the depth only
needs to cover the pipeline latency between producer and consumer.

---

## Summary: Framing Module Selection

| Task                                    | Module                          |
|-----------------------------------------|---------------------------------|
| Strip leading header beats              | `stream_header_stripper`        |
| Prepend header beats                    | `stream_header_inserter`        |
| Segment into fixed-size packets         | `stream_packetizer`             |
| Unpack fixed-size packets               | `stream_depacketizer`           |
| Insert `last` every N beats             | `stream_last_inserter`          |
| Remove `last` from interior frames      | `stream_last_remover`           |
| Count beats per frame                   | `stream_frame_length_counter`   |
| Detect SoF / EoF events                 | `stream_frame_detector`         |
| Detect stalled or idle stream           | `stream_timeout_detector`       |
| Detect prolonged absence of valid       | `stream_idle_detector`          |
| Generate one pulse per frame            | `stream_pulse_on_frame`         |
