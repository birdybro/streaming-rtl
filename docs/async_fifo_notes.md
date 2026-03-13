# Asynchronous FIFO Notes

## Overview

`stream_async_fifo` is the library's clock-domain crossing (CDC) primitive for
AXI-Stream data paths.  It transfers data safely between two unrelated clock
domains using Gray-coded pointers and multi-stage synchronizers.  This document
explains the underlying theory, the implementation choices made, and the
constraints that must be respected for reliable operation.

---

## Why Asynchronous FIFOs Need Gray Code

When a binary counter increments (e.g., from `0111` to `1000`), all four bits
change simultaneously.  A flip-flop sampling this counter from a different
clock domain may sample some bits at their old value and others at their new
value, producing a corrupt intermediate value that never actually occurred on
the counter.  This is a **metastability** hazard.

**Gray code** (also called reflected binary code) ensures that only **one bit
changes per increment**.  If a synchronizer samples a Gray-coded pointer at an
uncertain transition, the worst case is that it samples either the old value or
the new value — both of which are valid pointer states.  There is no
intermediate corrupt value.

```
Binary:  0 → 1 → 2 → 3 → 4 → 5 → 6 → 7
         000  001  010  011  100  101  110  111  ← up to 3 bits change at once

Gray:    0 → 1 → 2 → 3 → 4 → 5 → 6 → 7
         000  001  011  010  110  111  101  100  ← exactly 1 bit changes each step
```

The conversion between binary (`b`) and Gray (`g`) is:

```
g[i] = b[i] XOR b[i+1]          (binary to Gray)
b[i] = XOR of all g[j] for j >= i  (Gray to binary)
```

In SystemVerilog:

```systemverilog
// Binary to Gray
function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] b);
    return b ^ (b >> 1);
endfunction

// Gray to binary
function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
    logic [PTR_W-1:0] b;
    b[PTR_W-1] = g[PTR_W-1];
    for (int i = PTR_W-2; i >= 0; i--)
        b[i] = b[i+1] ^ g[i];
    return b;
endfunction
```

---

## How Gray-Code Pointers Work in the FIFO

The FIFO maintains two pointers, each one bit wider than the address bus
(`PTR_W = ADDR_W + 1`).  The extra bit is used to distinguish full from empty
when all address bits are equal.

| Pointer relationship | Meaning  |
|----------------------|----------|
| `rd_gray == wr_gray` | Empty    |
| MSBs differ, lower bits equal | Full |

**Full detection** (checked in the write clock domain):

```
wr_full = (wr_gray[PTR_W-1] != rd_gray_sync_wr[PTR_W-1]) &&
          (wr_gray[PTR_W-2] != rd_gray_sync_wr[PTR_W-2]) &&
          (wr_gray[PTR_W-3:0] == rd_gray_sync_wr[PTR_W-3:0])
```

This comparison works because in Gray code, the full condition is reached when
the write pointer has lapped the read pointer exactly once.

**Empty detection** (checked in the read clock domain):

```
fifo_empty = (rd_gray == wr_gray_sync_rd)
```

Equal Gray-coded pointers always mean empty, regardless of domain.

---

## The Synchronizer Chain (`SYNC_STAGES`)

Pointer synchronization uses a multi-flop chain to reduce the probability of
a metastable latch propagating to the rest of the logic.

```
wr_gray ──► [ FF1 ] ──► [ FF2 ] ──► (... SYNC_STAGES FFs) ──► wr_gray_sync_rd
                        sampled in m_clk domain
```

Each flip-flop stage reduces the probability of a metastable output surviving
to the next stage by a factor of approximately `2^(Tslack / τ)`, where `Tslack`
is the slack time available and `τ` is the technology-dependent metastability
resolution constant.

### Why SYNC_STAGES ≥ 2 Is Required

With only one synchronizer flip-flop, a metastable output from that flop feeds
directly into the comparator logic.  The probability of failure is not
negligible at production volumes.

With two flops (the standard minimum), the first flop resolves most metastable
events within one clock period; the second flop sees a stable value in the
vast majority of cases.  The remaining probability of failure is acceptably
small for most designs.

```
SYNC_STAGES = 2  →  adequate for most FPGA and ASIC designs
SYNC_STAGES = 3  →  use for very high clock frequencies or safety-critical designs
SYNC_STAGES = 4  →  rare; reserved for extreme reliability requirements
```

The library enforces `SYNC_STAGES >= 2` with a simulation-time `$fatal`:

```systemverilog
// synthesis translate_off
initial begin
    if (SYNC_STAGES < 2)
        $fatal(1, "stream_async_fifo: SYNC_STAGES must be >= 2, got %0d", SYNC_STAGES);
end
// synthesis translate_on
```

---

## Depth Sizing for CDC

The async FIFO must be deep enough to hold data produced during the
synchronizer latency.  The write pointer seen by the read domain is always
`SYNC_STAGES` read cycles stale.  Similarly, the read pointer seen by the
write domain is `SYNC_STAGES` write cycles stale.

A conservative rule:

```
min_depth >= max_burst_length + SYNC_STAGES * (s_clk_freq / m_clk_freq)
            (rounded up to next power of 2)
```

For typical 2-stage synchronizers and roughly equal clock frequencies:

```
min_depth >= max_burst_length + 4
```

**The recommended practice is `DEPTH >> max_burst_length`.**  Err on the side
of a larger FIFO.  If the write side is significantly faster than the read
side, the burst length available before the FIFO fills is correspondingly
smaller:

```
safe_burst_length = DEPTH * (m_clk_freq / s_clk_freq) - SYNC_STAGES
```

For a write-side clock of 200 MHz, read-side clock of 100 MHz, and DEPTH=16:

```
safe_burst_length = 16 * (100/200) - 2 = 6 beats
```

In this scenario, the write side can send at most 6 consecutive beats without
stalling, even with a fully-empty FIFO at the start of the burst.

---

## Reset Sequence for Dual-Domain FIFOs

The async FIFO has independent resets for each clock domain (`s_rst_n` and
`m_rst_n`).  Both resets must be applied **simultaneously** and held asserted
long enough to clear all registered state.

### Required Reset Procedure

1. Assert both `s_rst_n=0` and `m_rst_n=0` simultaneously (or de-assert them
   at the same wall-clock time, which is fine across domains).
2. Hold reset for at least `SYNC_STAGES + 2` cycles of **both** clocks.
3. De-assert `m_rst_n` first (read side).
4. De-assert `s_rst_n` last (write side).

This ordering ensures the read side is ready to accept data before the write
side can begin writing.

### Why Both Domains Must Be Reset Together

If only the write domain is reset, the write pointer resets to 0 but the read
domain's synchronized copy of the write pointer still holds the pre-reset
value.  The read side will incorrectly believe data is available and produce
garbage.  Similarly, if only the read domain is reset, the write side's
synchronized read pointer is stale and the full/empty logic misbehaves.

```systemverilog
// Example reset controller for a dual-domain design:
always_ff @(posedge s_clk) begin
    if (!por_n) s_rst_cnt <= '0;
    else if (!s_rst_released) s_rst_cnt <= s_rst_cnt + 1;
end
assign s_rst_n = (s_rst_cnt >= RESET_HOLD_CYCLES);

always_ff @(posedge m_clk) begin
    if (!por_n) m_rst_cnt <= '0;
    else if (!m_rst_released) m_rst_cnt <= m_rst_cnt + 1;
end
// Release m_clk domain first
assign m_rst_n = (m_rst_cnt >= RESET_HOLD_CYCLES);
```

---

## `stream_async_fifo` vs `stream_rate_matcher`

| Property               | `stream_async_fifo`               | `stream_rate_matcher`          |
|------------------------|-----------------------------------|--------------------------------|
| Clock domains          | Two independent clocks            | Single clock                   |
| Rate mismatch handling | Yes (absorbs bursts)              | Yes (inserts/removes idles)    |
| Use for CDC            | **Yes — correct choice**          | No — not safe for CDC          |
| Use for same-clock rate | No — synchronous FIFOs are better | Yes                           |
| Gray-code pointers     | Yes                               | N/A                            |
| Reset complexity       | Two domain resets required        | Single reset                   |

**Never** use `stream_rate_matcher` or any synchronous buffer for CDC.  The
absence of Gray-code synchronizers means the read side can observe
inconsistent pointer states and produce garbled data.

---

## Common Pitfalls

### 1. Forgetting to Reset Both Domains

Resetting only one domain leaves pointer synchronizers in an undefined state.
Always assert both `s_rst_n` and `m_rst_n` at power-on.

### 2. DEPTH Not a Power of 2

The full/empty detection logic relies on binary pointer arithmetic that
naturally wraps at a power-of-2 boundary.  Non-power-of-2 depths produce
incorrect full/empty detects.  The simulation guard catches this at time 0:

```
$fatal: stream_async_fifo: DEPTH must be a power of 2 >= 2, got 12
```

### 3. SYNC_STAGES = 1

A single synchronizer stage provides inadequate MTBF at production volumes.
The simulation guard prevents this configuration.

### 4. Treating the FIFO as a Delay Line

Some designers assume that because a beat takes `SYNC_STAGES` cycles to
"appear" on the read side, the FIFO can be used as a deterministic delay.
This is incorrect: the actual latency from write to read depends on the
relative phase and frequency of the two clocks and varies dynamically.

### 5. Sampling Unsynchronized Pointers

The binary pointer (`wr_bin`, `rd_bin`) must **never** be sampled in the
opposite clock domain.  Only the Gray-coded pointer is safe to synchronize.
The library enforces this by only exposing Gray-coded pointers to synchronizer
chains.

### 6. Under-Sized FIFO for Burst Traffic

A FIFO that is too shallow will assert `s_ready=0` (write-side full) before
the burst completes, stalling the producer.  If the producer cannot tolerate
stalls, size the FIFO to hold the entire worst-case burst plus
`2 * SYNC_STAGES` margin entries.

---

## Instantiation Reference

```systemverilog
stream_async_fifo #(
    .DATA_WIDTH  (32),     // bits per beat
    .DEPTH       (64),     // power-of-2; size for worst-case burst + margin
    .SYNC_STAGES (2),      // >= 2; use 3 for high-speed or safety-critical
    .USER_WIDTH  (1),
    .KEEP_WIDTH  (4)       // DATA_WIDTH / 8
) u_cdc_fifo (
    // Write (producer) domain
    .s_clk   (fast_clk),
    .s_rst_n (fast_rst_n),
    .s_valid (prod_valid),
    .s_ready (prod_ready),
    .s_data  (prod_data),
    .s_keep  (prod_keep),
    .s_last  (prod_last),
    .s_user  (prod_user),
    // Read (consumer) domain
    .m_clk   (slow_clk),
    .m_rst_n (slow_rst_n),
    .m_valid (cons_valid),
    .m_ready (cons_ready),
    .m_data  (cons_data),
    .m_keep  (cons_keep),
    .m_last  (cons_last),
    .m_user  (cons_user)
);
```

Add a `stream_register_slice` on the read side to fully register the output
backpressure path in the `m_clk` domain:

```systemverilog
stream_register_slice #(.DATA_WIDTH(32), .KEEP_WIDTH(4)) u_rd_slice (
    .clk   (slow_clk),   .rst_n (slow_rst_n),
    .s_valid (cons_valid), .s_ready (cons_ready),
    // ... forward to downstream logic
);
```
