// ==============================================================================
// File    : stream_upsizer.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Combines RATIO consecutive narrow input beats into one wide output beat.
//   The master-side data width is M_DATA_WIDTH = S_DATA_WIDTH * RATIO.
//   m_last is asserted whenever the accumulated word was terminated by an
//   s_last on the input (even if fewer than RATIO beats were received).
//   m_keep reflects the per-byte enables of all RATIO narrow slices; bytes
//   in positions not written before s_last are forced to keep=0.
//
//   Operation:
//     1. Accumulate RATIO narrow beats into acc_data/acc_keep (beat 0…RATIO-1).
//     2. On s_last OR when the beat counter reaches RATIO-1, merge the current
//        beat with the accumulator via combinatorial next_out_* logic and
//        latch the result into the output register (out_*).
//     3. Hold the output register until the downstream accepts (m_ready).
//        The upstream is stalled only while the output register is occupied
//        and the downstream is not ready (s_ready = ~out_valid | m_ready).
//
//   Two-level buffering (acc → out) allows zero-bubble back-to-back wide
//   transfers when m_ready is held high.
//
// Parameters:
//   S_DATA_WIDTH – narrow input data width in bits (default 8)
//   RATIO        – number of narrow beats per wide beat (default 4)
//   USER_WIDTH   – sideband user width in bits (default 1)
//   Derived:
//     M_DATA_WIDTH = S_DATA_WIDTH * RATIO
// ==============================================================================

`default_nettype none

module stream_upsizer #(
    parameter int S_DATA_WIDTH = 8,
    parameter int RATIO        = 4,
    parameter int USER_WIDTH   = 1
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset

    // Narrow slave (input) interface
    input  logic                            s_valid,
    output logic                            s_ready,
    input  logic [S_DATA_WIDTH-1:0]         s_data,
    input  logic [S_KEEP_WIDTH-1:0]         s_keep,
    input  logic                            s_last,
    input  logic [USER_WIDTH-1:0]           s_user,

    // Wide master (output) interface
    output logic                            m_valid,
    input  logic                            m_ready,
    output logic [M_DATA_WIDTH-1:0]         m_data,
    output logic [M_KEEP_WIDTH-1:0]         m_keep,
    output logic                            m_last,
    output logic [USER_WIDTH-1:0]           m_user
);

    // -------------------------------------------------------------------------
    // Derived parameters
    // -------------------------------------------------------------------------
    localparam int M_DATA_WIDTH = S_DATA_WIDTH * RATIO;
    localparam int S_KEEP_WIDTH = S_DATA_WIDTH / 8;
    localparam int M_KEEP_WIDTH = M_DATA_WIDTH / 8;
    localparam int CNT_WIDTH    = (RATIO > 1) ? $clog2(RATIO) : 1;

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------
    // Accumulation registers: hold beats 0 … beat_cnt-1
    logic [M_DATA_WIDTH-1:0]  acc_data;
    logic [M_KEEP_WIDTH-1:0]  acc_keep;
    logic [USER_WIDTH-1:0]    acc_user;

    // Output holding register: holds completed wide beat until m_ready
    logic [M_DATA_WIDTH-1:0]  out_data;
    logic [M_KEEP_WIDTH-1:0]  out_keep;
    logic [USER_WIDTH-1:0]    out_user;
    logic                     out_last;
    logic                     out_valid;

    logic [CNT_WIDTH-1:0]     beat_cnt;

    // -------------------------------------------------------------------------
    // Handshake
    // -------------------------------------------------------------------------
    assign s_ready = ~out_valid | m_ready;
    assign m_valid = out_valid;
    assign m_data  = out_data;
    assign m_keep  = out_keep;
    assign m_last  = out_last;
    assign m_user  = out_user;

    // -------------------------------------------------------------------------
    // Combinatorial next-output computation
    //   Merges the current incoming beat (position beat_cnt) with the already
    //   accumulated beats (acc_*).  Unused positions (> beat_cnt) get keep=0.
    //   This is only committed to the output register when emitting.
    // -------------------------------------------------------------------------
    logic [M_DATA_WIDTH-1:0]  next_out_data;
    logic [M_KEEP_WIDTH-1:0]  next_out_keep;

    always_comb begin
        // Start from the accumulator (beats 0 … beat_cnt-1 already written)
        next_out_data = acc_data;
        next_out_keep = acc_keep;

        // Overlay the current (last) beat
        next_out_data[int'(beat_cnt) * S_DATA_WIDTH +: S_DATA_WIDTH] = s_data;
        next_out_keep[int'(beat_cnt) * S_KEEP_WIDTH +: S_KEEP_WIDTH] = s_keep;

        // Zero keep for positions beyond beat_cnt (packet ended early)
        for (int i = 0; i < RATIO; i++) begin
            if (i > int'(beat_cnt)) begin
                next_out_keep[i * S_KEEP_WIDTH +: S_KEEP_WIDTH] = '0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc_data  <= '0;
            acc_keep  <= '0;
            acc_user  <= '0;
            out_data  <= '0;
            out_keep  <= '0;
            out_user  <= '0;
            out_last  <= 1'b0;
            out_valid <= 1'b0;
            beat_cnt  <= '0;
        end else begin

            // ----------------------------------------------------------------
            // Output side: consume the holding register
            // ----------------------------------------------------------------
            if (out_valid && m_ready) begin
                out_valid <= 1'b0;  // May be overridden below
            end

            // ----------------------------------------------------------------
            // Input side: accumulate or emit
            // ----------------------------------------------------------------
            if (s_valid && s_ready) begin
                if (s_last || beat_cnt == CNT_WIDTH'(RATIO - 1)) begin
                    // --- Emit ---
                    // Transfer merged accumulator + current beat to output reg
                    out_data  <= next_out_data;
                    out_keep  <= next_out_keep;
                    out_last  <= s_last;
                    out_user  <= s_user;
                    out_valid <= 1'b1;   // Overrides the clear above if both fire
                    // Reset beat counter and clear accumulator for next M-beat
                    beat_cnt  <= '0;
                    acc_data  <= '0;
                    acc_keep  <= '0;
                end else begin
                    // --- Accumulate ---
                    acc_data[beat_cnt * S_DATA_WIDTH +: S_DATA_WIDTH] <= s_data;
                    acc_keep[beat_cnt * S_KEEP_WIDTH +: S_KEEP_WIDTH] <= s_keep;
                    acc_user  <= s_user;
                    beat_cnt  <= beat_cnt + 1'b1;
                end
            end

        end
    end

endmodule

`default_nettype wire
