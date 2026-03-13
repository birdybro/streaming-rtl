# Ready/Valid Handshake Basics

## What Is Ready/Valid?

The ready/valid (also called valid/ready or AXI-Stream) handshake is the
fundamental flow-control protocol used throughout this library.  Every module
has:

- **`valid`** (source → sink): the source asserts this when it is presenting
  data that should be consumed.
- **`ready`** (sink → source): the sink asserts this when it is able to accept
  data.

**A transfer (beat) occurs on the rising clock edge when both `valid` and
`ready` are simultaneously asserted.**

```
          ┌──────┐   valid, data, keep, last, user   ┌──────┐
 upstream │      │ ─────────────────────────────────► │      │ downstream
  (source)│      │ ◄───────────────────── ready ───── │      │ (sink)
          └──────┘                                    └──────┘
```

---

## Timing Diagrams

### Normal Transfer (no stalls)

```
clk    ____╱‾╲____╱‾╲____╱‾╲____╱‾╲____╱‾╲____
valid  ________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲______
ready  ________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲______
data   ---------[  A  ][  B  ][  C  ]-----------
                 ^     ^     ^
                 T1    T2    T3  (transfers)
```

Beats A, B, and C are all transferred at T1, T2, T3 respectively because both
`valid` and `ready` are high at each rising clock edge.

### Source Stall (valid deasserted)

```
clk    ____╱‾╲____╱‾╲____╱‾╲____╱‾╲____╱‾╲____
valid  ________╱‾‾‾╲____________╱‾‾‾╲__________
ready  ____________________________╱‾‾‾‾‾‾‾╲____
data   ---------[  A  ]-----------[  B  ]---------
                 ^                       ^
                 T1                      T2
```

At T1, `valid=1` and `ready=0`; no transfer occurs (sink is busy).
At T2, both are high; beat B is transferred.

### Sink Stall (ready deasserted)

```
clk    ____╱‾╲____╱‾╲____╱‾╲____╱‾╲____╱‾╲____
valid  ________╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲________
ready  ____________╱‾‾‾╲________╱‾‾‾‾‾‾‾╲______
data   ---------[  A  ][  A  ]--[  B  ][  C  ]--
                       ^              ^  ^
                       T1             T2 T3
```

Beat A is presented for two cycles before being accepted at T1 because `ready`
was deasserted in the first cycle.

---

## Protocol Rules

### Source Rules

1. **`valid` must not be deasserted without a transfer.**  Once the source
   raises `valid` it must hold `valid` and the associated `data`, `keep`,
   `last`, and `user` signals stable until the transfer is accepted (`ready=1`).

   ```
   // ILLEGAL: dropping valid before ready asserted
   clk    ___╱‾╲___╱‾╲___╱‾╲___
   valid  _____╱‾‾‾╲___________   ← valid dropped without ready being high
   ready  ___________________╱‾
   ```

2. **`valid` may be asserted without waiting for `ready`.**  The source does
   not need to "see" `ready` high before asserting `valid`.

3. **`valid` may be asserted combinationally from inputs**, but `ready` must
   not create a combinational loop back to `valid` through the source logic.

### Sink Rules

1. **`ready` may be deasserted at any time**, even when `valid` is high.  The
   sink makes no guarantee about when it will assert `ready`.

2. **`ready` may depend combinationally on `valid`** (e.g., a FIFO may wait
   for a push event to trigger a read).  This is legal but can cause long
   combinational paths.

3. **`ready` must not be held permanently low** once a transfer is expected;
   doing so deadlocks the stream.

### Handshake Summary Table

| `valid` | `ready` | Transfer? | Notes                                |
|---------|---------|-----------|--------------------------------------|
| 0       | 0       | No        | Both sides idle                      |
| 0       | 1       | No        | Sink ready but no data available     |
| 1       | 0       | No        | Source has data; sink not ready      |
| 1       | 1       | **Yes**   | Beat transferred on rising clock edge|

---

## Correct vs Incorrect Usage Examples

### Correct: Hold valid until accepted

```systemverilog
always_ff @(posedge clk) begin
    if (!rst_n) begin
        out_valid <= 1'b0;
        out_data  <= '0;
    end else begin
        if (!out_valid || m_ready) begin
            // Only update when output is free or being consumed
            out_valid <= new_data_available;
            out_data  <= new_data;
        end
    end
end
```

### Incorrect: Deassert valid without transfer

```systemverilog
// BUG: This clears valid every cycle, violating the protocol.
always_ff @(posedge clk) begin
    out_valid <= 1'b0;           // ← always deasserts, even if !m_ready
    if (new_data_available) begin
        out_valid <= 1'b1;
        out_data  <= new_data;
    end
end
```

### Correct: Combinational ready based on internal state

```systemverilog
// A FIFO can assert s_ready whenever it is not full
assign s_ready = ~fifo_full;
```

### Incorrect: Combinational ready → valid loop

```systemverilog
// BUG: valid depends on ready, which depends on valid — combinational loop
assign m_valid = s_valid & m_ready;   // ← creates a combinational loop
```

---

## Latency vs Throughput

The handshake does not itself add latency, but pipeline stages that register
signals introduce one cycle of latency each.  The tradeoffs are:

| Module                   | Latency   | Ready path  | Best for                        |
|--------------------------|-----------|-------------|---------------------------------|
| `stream_pipeline_stage`  | 1 cycle   | Combinational | Short pipelines, low area     |
| `stream_register_slice`  | 1–2 cycles| Registered  | Long pipelines, high frequency  |
| `stream_skid_buffer`     | 1 cycle   | Registered  | Minimal register-slice variant  |
| `stream_fifo`            | ≥1 cycle  | Registered  | Burst absorption                |

**Throughput** is unaffected by these choices as long as the pipeline is not
stalled.  Full throughput is 1 transfer per clock cycle regardless of the
number of stages.

---

## Extending the Handshake: last, keep, user

### `last` — End of Frame

`last` is asserted on the final beat of a frame, analogous to `TLAST` in
AXI4-Stream.  It is transferred together with the beat it belongs to (when
both `valid` and `ready` are high).  A frame consists of one or more beats,
with exactly one `last=1` beat per frame.

```
clk    ___╱‾╲___╱‾╲___╱‾╲___╱‾╲___
valid  _______╱‾‾‾‾‾‾‾‾‾‾‾‾‾╲_____
ready  _______╱‾‾‾‾‾‾‾‾‾‾‾‾‾╲_____
data   --------[ D0 ][ D1 ][ D2 ]--
last   ___________________________╱‾  (D2 is last beat of this frame)
```

### `keep` — Byte Enables

`keep` has one bit per byte of `data`, indicating which bytes in the beat
contain valid data.  Typically all bits are `1`.  The final beat of a frame
may have trailing bytes disabled (`keep` bits cleared) to signal a partial
beat.

```
// Example: DATA_WIDTH=32, last beat has only 2 valid bytes
m_keep = 4'b0011;  // bytes [7:0] and [15:8] valid; [23:16] and [31:24] invalid
m_last = 1'b1;
```

### `user` — Sideband Metadata

`user` carries per-beat sideband information (e.g., error flags, source IDs,
timestamps).  It travels with the beat and obeys the same handshake rules.
Its width is set by the `USER_WIDTH` parameter (default 1).

---

## Common Pitfalls

1. **Glitching data after valid** – once `valid` is asserted, `data`, `keep`,
   `last`, and `user` must all remain stable until the transfer occurs.

2. **Asserting valid based on ready** – creates a zero-cycle combinational
   loop.  Use a register to break any feedback path.

3. **Forgetting last** – frame-aware modules (`stream_header_stripper`,
   `stream_packetizer`, etc.) require `last` to be asserted on the final
   beat.  Omitting it will leave the module stuck in payload state.

4. **Ignoring ready** – if a source drives `valid=1` continuously but never
   checks `ready`, it will silently drop beats when the sink stalls.

5. **Holding ready permanently low** – deadlocks the stream.  A sink should
   always eventually assert `ready`, even if only briefly.
