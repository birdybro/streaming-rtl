# Arbitration Patterns

## Overview

The arbitration modules in `streaming-rtl` cover the full range of
multi-stream topologies: N-to-1 selection (arbiters), 1-to-N fan-out
(broadcast, demux), and N-to-1 combination (merge, join).  This guide
explains when to choose each module and how to compose them into larger
routing fabrics.

---

## Fixed Priority vs Round-Robin

### `stream_arbiter_fixed_priority`

The fixed-priority arbiter always grants the numerically lowest input that has
valid data.  Input 0 has the highest priority; input N−1 has the lowest.

**Advantages:**
- Deterministic latency for high-priority inputs.
- Zero extra state; the grant is computed purely combinationally from `s_valid`.

**Disadvantages:**
- Lower-priority inputs can starve indefinitely if a higher-priority input
  produces data continuously.
- Not suitable when all inputs must make forward progress.

**Use when:**
- One input carries critical or time-sensitive data and must never be delayed.
- Lower-priority inputs carry best-effort traffic that can tolerate starvation.
- Example: a management control channel (priority 0) and a bulk data channel
  (priority 1).

```systemverilog
stream_arbiter_fixed_priority #(
    .NUM_INPUTS (3),
    .DATA_WIDTH (8)
) u_fp_arb (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (s_valid_3),
    .s_ready (s_ready_3),
    .s_data  (s_data_3),
    .s_keep  (s_keep_3),
    .s_last  (s_last_3),
    .s_user  (s_user_3),
    .m_valid (m_valid), .m_ready (m_ready),
    .m_data  (m_data),  .m_keep  (m_keep),
    .m_last  (m_last),  .m_user  (m_user),
    .grant   (grant_3)
);
```

### `stream_arbiter_round_robin`

The round-robin arbiter cycles the grant token among all inputs that have
valid data, advancing the token after each **complete frame** (on the accepted
`s_last` beat).

**Advantages:**
- Prevents starvation: every active input is guaranteed service within
  `NUM_INPUTS` frames.
- Frame-locked: a single source holds the grant for its entire frame,
  preventing interleaving.

**Disadvantages:**
- Higher-priority traffic cannot preempt an in-progress frame.
- Slightly more state than fixed-priority (round-robin pointer register).

**Use when:**
- Multiple equal-importance sources share a single output link.
- Frame integrity must be maintained (no mid-frame interleaving).
- Example: four CPU cores sharing a PCIe transmit lane.

```systemverilog
stream_arbiter_round_robin #(
    .NUM_INPUTS (4),
    .DATA_WIDTH (32),
    .KEEP_WIDTH (4)
) u_rr_arb (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (s_valid_4),
    .s_ready (s_ready_4),
    .s_data  (s_data_4),
    .s_keep  (s_keep_4),
    .s_last  (s_last_4),
    .s_user  (s_user_4),
    .m_valid (m_valid), .m_ready (m_ready),
    .m_data  (m_data),  .m_keep  (m_keep),
    .m_last  (m_last),  .m_user  (m_user),
    .grant   (grant_4)
);
```

### Frame-Locked Arbitration Explained

Frame locking means the arbiter never switches away from the currently-granted
source until it sees `s_last` accepted.  This is critical for packetised
protocols where all beats belonging to a frame must arrive in order and without
interruption.

```
Without frame lock (incorrect for packets):
  T0: grant=0, data=A0
  T1: grant=1, data=B0   ← grant switched mid-frame!
  T2: grant=0, data=A1   ← A0 and A1 are separated

With frame lock (correct):
  T0: grant=0, data=A0
  T1: grant=0, data=A1, last=1   ← full frame A transferred
  T2: grant=1, data=B0
  T3: grant=1, data=B1, last=1   ← full frame B transferred
```

---

## Mux and Demux

### `stream_mux`

A combinational N-to-1 mux controlled by a `select` signal.  Unlike an
arbiter, the mux does not auto-select: the caller drives `select` to choose
the active input.

**Use when:**
- A state machine outside the streaming path decides which stream to route.
- The routing decision is made before data arrives (e.g., based on a channel
  number in a control register).

```systemverilog
stream_mux #(.NUM_INPUTS(2), .DATA_WIDTH(8)) u_mux (
    .clk     (clk),   .rst_n   (rst_n),
    .select  (channel_select),   // 1-bit: 0=ch0, 1=ch1
    .s_valid (s_valid_2),
    .s_ready (s_ready_2),
    .s_data  (s_data_2),
    // ... other ports
    .m_valid (m_valid), .m_ready (m_ready), .m_data (m_data)
);
```

### `stream_demux`

A combinational 1-to-N demux controlled by a `select` signal.  Routes the
single input to one of N outputs.

**Use when:**
- A header field or external signal determines the routing destination.
- You want to classify traffic at a chokepoint (e.g., after parsing a type
  field) and dispatch to separate processing paths.

---

## Broadcast (`stream_broadcast`)

`stream_broadcast` fans one source out to N destinations simultaneously.
Every output receives every beat.  The module uses a **done mask** to track
which outputs have already accepted the current beat, so that fast consumers
are not forced to re-accept a beat while a slow consumer catches up.

### Done-Mask Pattern

```
Beat X presented on s_data, s_valid=1:
  Cycle 0: output 0 ready=1 → done_mask[0]=1; outputs 1,2,3 not yet done
  Cycle 1: output 2 ready=1 → done_mask[2]=1; outputs 1,3 not yet done
  Cycle 2: outputs 1,3 ready=1 → all done; s_ready=1; beat X consumed
```

The input beat is held for as many cycles as needed for the slowest consumer.

### Use when

- One stream feeds multiple independent processing paths (fan-out).
- All downstream consumers must process every beat (no selective routing).
- Consumers may have different backpressure characteristics.

```systemverilog
stream_broadcast #(
    .NUM_OUTPUTS (3),
    .DATA_WIDTH  (8)
) u_bcast (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (s_valid), .s_ready (s_ready),
    .s_data  (s_data),  .s_keep  (s_keep),
    .s_last  (s_last),  .s_user  (s_user),
    .m_valid (m_valid_3),
    .m_ready (m_ready_3),
    .m_data  (m_data_3),
    .m_keep  (m_keep_3),
    .m_last  (m_last_3),
    .m_user  (m_user_3)
);
```

---

## Merge vs Join

These two modules both combine N inputs into 1 output, but they have very
different semantics.

### `stream_merge` — First-Valid Wins

`stream_merge` is a permissive combiner.  It forwards whichever input asserts
`valid` first.  If multiple inputs are simultaneously valid, a fixed-priority
or round-robin policy determines which is forwarded (implementation-dependent).
No synchronisation between inputs is required.

**Use when:**
- Inputs are mutually exclusive (only one is ever valid at a time).
- You want the lowest-latency combination of independent streams.
- Example: two state machines that produce events at different times and the
  consumer only needs to see each event in arrival order.

### `stream_join` — All-Valid Synchronisation

`stream_join` waits until **all** N inputs simultaneously present valid data,
then accepts them all in the same cycle and produces a single wide output beat
whose data is the concatenation of all input data fields.

`m_last` = AND of all `s_last` inputs — the output frame ends only when all
input frames end in the same beat.

**Use when:**
- Multiple parallel processing paths must produce one combined result per beat.
- Inputs are derived from the same original stream (e.g., two processing
  pipelines fed from a broadcast).
- You need guaranteed alignment between inputs.

```systemverilog
// Join two 8-bit streams into one 16-bit output beat
stream_join #(
    .NUM_INPUTS (2),
    .DATA_WIDTH (8)    // per-input width; output is 2*8 = 16 bits
) u_join (
    .clk     (clk),   .rst_n   (rst_n),
    .s_valid (join_s_valid_2),
    .s_ready (join_s_ready_2),
    .s_data  (join_s_data_2),   // [1:0][7:0]
    .s_keep  (join_s_keep_2),
    .s_last  (join_s_last_2),
    .s_user  (join_s_user_2),
    .m_valid (m_valid), .m_ready (m_ready),
    .m_data  (m_data),           // [15:0]
    .m_keep  (m_keep),
    .m_last  (m_last),
    .m_user  (m_user)
);
```

### Merge vs Join Summary

| Property              | `stream_merge`    | `stream_join`          |
|-----------------------|-------------------|------------------------|
| Synchronisation       | None              | All inputs must be valid simultaneously |
| Output data width     | DATA_WIDTH        | NUM_INPUTS × DATA_WIDTH |
| `m_last` semantics    | First input's last| AND of all inputs' last |
| Inputs mutually exclusive? | Preferred    | Not required           |
| Risk of deadlock      | None              | Yes if inputs get out of step |

---

## Building Larger N-Way Arbiters

The library provides arbiters up to any `NUM_INPUTS`.  For very large N
(e.g., 64 inputs), consider a tree topology to reduce the combinational depth
of the priority encoder:

```
Level 0: 8× stream_arbiter_round_robin #(.NUM_INPUTS(8))  → 8 intermediate outputs
Level 1: 1× stream_arbiter_round_robin #(.NUM_INPUTS(8))  → final output
```

Each level adds one round-robin stage latency.  Frame-lock is preserved at
every level because each arbiter locks its grant on `last`.

---

## Starvation Prevention

When using `stream_arbiter_fixed_priority`, lower-priority inputs may starve
permanently.  Mitigation strategies:

1. **Use round-robin instead** — the simplest solution when all inputs have
   equal importance.

2. **Credit-based throttling** — limit the number of consecutive frames the
   highest-priority input may send before yielding.  Implement this by
   counting frames and temporarily masking the high-priority `s_valid`.

3. **Leaky-bucket rate limiting** — insert a `stream_rate_matcher` on the
   high-priority path to cap its average throughput, leaving bandwidth for
   lower-priority inputs.

4. **Ageing** — a custom arbiter that promotes a lower-priority input's
   priority after it has been starved for more than T cycles.  Not provided
   in this library but straightforward to implement using the grant output of
   `stream_arbiter_fixed_priority` as the ageing trigger.
