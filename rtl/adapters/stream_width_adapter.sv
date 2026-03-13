// ==============================================================================
// File    : stream_width_adapter.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Generic streaming width adapter.  A single parameterised module that acts
//   as an upsizer, downsizer, or transparent pass-through depending on the
//   relationship between S_DATA_WIDTH and M_DATA_WIDTH.
//
//     S_DATA_WIDTH < M_DATA_WIDTH  →  upsizer  (combine narrow → wide)
//     S_DATA_WIDTH > M_DATA_WIDTH  →  downsizer (split   wide  → narrow)
//     S_DATA_WIDTH == M_DATA_WIDTH →  pass-through
//
//   Both widths must be multiples of 8; the larger must be an integer
//   multiple of the smaller.
//
//   Upsizer details (S < M):
//     RATIO = M_DATA_WIDTH / S_DATA_WIDTH narrow beats are collected into one
//     wide beat.  If s_last arrives before RATIO beats the word is flushed
//     early; unused keep lanes are forced to zero.  A two-level (acc → out)
//     buffer allows zero-bubble back-to-back transfers when m_ready is high.
//
//   Downsizer details (S > M):
//     RATIO = S_DATA_WIDTH / M_DATA_WIDTH narrow beats are emitted per wide
//     input word.  The slave is stalled while beats are being emitted.
//     m_last is asserted on the final narrow beat.
//
// Parameters:
//   S_DATA_WIDTH – slave  data width in bits (default 8)
//   M_DATA_WIDTH – master data width in bits (default 32)
//   USER_WIDTH   – sideband user width in bits (default 1)
// ==============================================================================

`default_nettype none

module stream_width_adapter #(
    parameter int S_DATA_WIDTH = 8,
    parameter int M_DATA_WIDTH = 32,
    parameter int USER_WIDTH   = 1
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset

    // Slave (input) interface
    input  logic                        s_valid,
    output logic                        s_ready,
    input  logic [S_DATA_WIDTH-1:0]     s_data,
    input  logic [S_DATA_WIDTH/8-1:0]   s_keep,
    input  logic                        s_last,
    input  logic [USER_WIDTH-1:0]       s_user,

    // Master (output) interface
    output logic                        m_valid,
    input  logic                        m_ready,
    output logic [M_DATA_WIDTH-1:0]     m_data,
    output logic [M_DATA_WIDTH/8-1:0]   m_keep,
    output logic                        m_last,
    output logic [USER_WIDTH-1:0]       m_user
);

    // -------------------------------------------------------------------------
    // Local parameters (shared across generate branches)
    // -------------------------------------------------------------------------
    localparam int S_KEEP_WIDTH = S_DATA_WIDTH / 8;
    localparam int M_KEEP_WIDTH = M_DATA_WIDTH / 8;

    // =========================================================================
    generate

        // =====================================================================
        // Pass-through: widths are equal
        // =====================================================================
        if (S_DATA_WIDTH == M_DATA_WIDTH) begin : gen_passthrough

            assign s_ready = m_ready;
            assign m_valid = s_valid;
            assign m_data  = s_data;
            assign m_keep  = s_keep;
            assign m_last  = s_last;
            assign m_user  = s_user;

        // =====================================================================
        // Upsizer: S_DATA_WIDTH < M_DATA_WIDTH
        //   Combine RATIO narrow beats into one wide beat.
        // =====================================================================
        end else if (S_DATA_WIDTH < M_DATA_WIDTH) begin : gen_upsizer

            localparam int RATIO     = M_DATA_WIDTH / S_DATA_WIDTH;
            localparam int CNT_WIDTH = (RATIO > 1) ? $clog2(RATIO) : 1;

            // Accumulation registers (beats 0 … beat_cnt-1)
            logic [M_DATA_WIDTH-1:0]  acc_data;
            logic [M_KEEP_WIDTH-1:0]  acc_keep;
            logic [USER_WIDTH-1:0]    acc_user;

            // Output holding register
            logic [M_DATA_WIDTH-1:0]  out_data;
            logic [M_KEEP_WIDTH-1:0]  out_keep;
            logic [USER_WIDTH-1:0]    out_user;
            logic                     out_last;
            logic                     out_valid;

            logic [CNT_WIDTH-1:0]     beat_cnt;

            // Handshake
            assign s_ready = ~out_valid | m_ready;
            assign m_valid = out_valid;
            assign m_data  = out_data;
            assign m_keep  = out_keep;
            assign m_last  = out_last;
            assign m_user  = out_user;

            // Combinatorial next-output: merge accumulator with current beat
            logic [M_DATA_WIDTH-1:0]  next_out_data;
            logic [M_KEEP_WIDTH-1:0]  next_out_keep;

            always_comb begin
                next_out_data = acc_data;
                next_out_keep = acc_keep;
                next_out_data[int'(beat_cnt) * S_DATA_WIDTH +: S_DATA_WIDTH] = s_data;
                next_out_keep[int'(beat_cnt) * S_KEEP_WIDTH +: S_KEEP_WIDTH] = s_keep;
                for (int i = 0; i < RATIO; i++) begin
                    if (i > int'(beat_cnt)) begin
                        next_out_keep[i * S_KEEP_WIDTH +: S_KEEP_WIDTH] = '0;
                    end
                end
            end

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
                    // Consume output
                    if (out_valid && m_ready) begin
                        out_valid <= 1'b0;
                    end

                    // Accept input
                    if (s_valid && s_ready) begin
                        if (s_last || beat_cnt == CNT_WIDTH'(RATIO - 1)) begin
                            // Emit wide beat
                            out_data  <= next_out_data;
                            out_keep  <= next_out_keep;
                            out_last  <= s_last;
                            out_user  <= s_user;
                            out_valid <= 1'b1;
                            beat_cnt  <= '0;
                            acc_data  <= '0;
                            acc_keep  <= '0;
                        end else begin
                            // Accumulate
                            acc_data[beat_cnt * S_DATA_WIDTH +: S_DATA_WIDTH] <= s_data;
                            acc_keep[beat_cnt * S_KEEP_WIDTH +: S_KEEP_WIDTH] <= s_keep;
                            acc_user  <= s_user;
                            beat_cnt  <= beat_cnt + 1'b1;
                        end
                    end
                end
            end

        // =====================================================================
        // Downsizer: S_DATA_WIDTH > M_DATA_WIDTH
        //   Split one wide beat into RATIO narrow beats.
        // =====================================================================
        end else begin : gen_downsizer

            localparam int RATIO     = S_DATA_WIDTH / M_DATA_WIDTH;
            localparam int CNT_WIDTH = (RATIO > 1) ? $clog2(RATIO) : 1;

            logic [S_DATA_WIDTH-1:0]  latch_data;
            logic [S_KEEP_WIDTH-1:0]  latch_keep;
            logic                     latch_last;
            logic [USER_WIDTH-1:0]    latch_user;
            logic                     latch_valid;

            logic [CNT_WIDTH-1:0]     beat_cnt;

            // Accept only when idle
            assign s_ready = ~latch_valid;
            assign m_valid = latch_valid;

            assign m_data = latch_data[beat_cnt * M_DATA_WIDTH +: M_DATA_WIDTH];
            assign m_keep = latch_keep[beat_cnt * M_KEEP_WIDTH +: M_KEEP_WIDTH];
            assign m_last = latch_last && (beat_cnt == CNT_WIDTH'(RATIO - 1));
            assign m_user = latch_user;

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    latch_data  <= '0;
                    latch_keep  <= '0;
                    latch_last  <= 1'b0;
                    latch_user  <= '0;
                    latch_valid <= 1'b0;
                    beat_cnt    <= '0;
                end else begin
                    // Latch new wide beat
                    if (s_valid && s_ready) begin
                        latch_data  <= s_data;
                        latch_keep  <= s_keep;
                        latch_last  <= s_last;
                        latch_user  <= s_user;
                        latch_valid <= 1'b1;
                        beat_cnt    <= '0;
                    end

                    // Advance narrow beat counter
                    if (latch_valid && m_ready) begin
                        if (beat_cnt == CNT_WIDTH'(RATIO - 1)) begin
                            latch_valid <= 1'b0;
                            beat_cnt    <= '0;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                        end
                    end
                end
            end

        end
    endgenerate

endmodule

`default_nettype wire
