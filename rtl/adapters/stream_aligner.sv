// ==============================================================================
// File    : stream_aligner.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Byte-aligns (left-justifies / packs) a stream whose keep signal may
//   contain holes (non-contiguous valid bytes).  Each input beat is repacked
//   so that all valid bytes appear contiguously starting at byte lane 0
//   (the least-significant lane), and the corresponding keep bits are all 1
//   for valid lanes and 0 for unused lanes.
//
//   This is a single-beat, combinational transformation: one input beat
//   produces exactly one output beat with the same last/user signals.  The
//   output DATA_WIDTH matches the input DATA_WIDTH; if the packed byte count
//   is less than KEEP_WIDTH the upper keep bits are simply forced to 0.
//
//   Algorithm (combinational, no latency):
//     1. Compute a prefix-sum array: pfx[i] = number of set keep bits in
//        s_keep[i-1:0]  (i.e. how many valid bytes precede byte lane i).
//     2. For each input lane i where s_keep[i]=1, write s_data[i] to output
//        lane pfx[i] and assert packed_keep[pfx[i]].
//
//   The result is equivalent to a hardware priority-encoder-driven barrel
//   shift.  Variable part-select widths (the `+:` form with constant width)
//   are used so every synthesis tool can infer the correct mux structure.
//
//   Because the transform is purely combinational the module incurs zero
//   additional latency and is always ready (s_ready = m_ready).
//
// Parameters:
//   DATA_WIDTH – data bus width in bits (default 32)
//   USER_WIDTH – sideband user width in bits (default 1)
//   KEEP_WIDTH – byte-enable width; should equal DATA_WIDTH/8 (default)
// ==============================================================================

`default_nettype none

module stream_aligner #(
    parameter int DATA_WIDTH = 32,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset (kept for interface
                          // uniformity; this module is purely combinational)

    // Slave (input) interface
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Master (output) interface
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // Prefix-sum counter width: must hold values 0 … KEEP_WIDTH
    // -------------------------------------------------------------------------
    localparam int CNT_W = $clog2(KEEP_WIDTH + 1) + 1;

    // -------------------------------------------------------------------------
    // Combinatorial byte-packing
    //
    //   pfx[i] = number of set bits in s_keep[i-1:0]
    //          = output lane index for input byte i (when s_keep[i]=1)
    //
    //   The prefix sum is built with a sequential blocking loop inside
    //   always_comb so each iteration's result feeds the next.  No
    //   automatic/static variable is needed.
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]  packed_data;
    logic [KEEP_WIDTH-1:0]  packed_keep;

    logic [CNT_W-1:0] pfx [0:KEEP_WIDTH];  // pfx[0]=0; pfx[i+1]=pfx[i]+keep[i]

    always_comb begin
        // Build prefix sum
        pfx[0] = '0;
        for (int i = 0; i < KEEP_WIDTH; i++) begin
            pfx[i+1] = pfx[i] + CNT_W'(s_keep[i]);
        end

        // Place each valid input byte at its packed output position
        packed_data = '0;
        packed_keep = '0;
        for (int i = 0; i < KEEP_WIDTH; i++) begin
            if (s_keep[i]) begin
                packed_data[pfx[i] * 8 +: 8] = s_data[i * 8 +: 8];
                packed_keep[pfx[i]]           = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Purely combinational pass-through with packed data/keep
    // -------------------------------------------------------------------------
    assign s_ready = m_ready;
    assign m_valid = s_valid;
    assign m_data  = packed_data;
    assign m_keep  = packed_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    // Suppress unused-signal warning for clk/rst_n (interface uniformity)
    // synthesis translate_off
    logic unused_ok;
    assign unused_ok = clk ^ rst_n;
    // synthesis translate_on

endmodule

`default_nettype wire
