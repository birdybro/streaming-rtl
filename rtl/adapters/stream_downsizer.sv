// ==============================================================================
// File    : stream_downsizer.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Splits one wide input beat into RATIO consecutive narrow output beats.
//   The slave-side data width is S_DATA_WIDTH = M_DATA_WIDTH * RATIO.
//   m_last is asserted on the final narrow beat when the wide word carried
//   s_last.  m_keep reflects the per-byte enables of each narrow slice.
//
//   Operation:
//     1. Latch one wide beat from the slave when idle (latch_valid=0).
//     2. Emit narrow beats one at a time in order beat 0 … RATIO-1.
//     3. On the last beat, clear latch_valid and accept the next wide beat.
//
//   The slave is stalled (s_ready=0) while a wide word is being emitted.
//   An optional one-cycle overlap optimisation is NOT included here to keep
//   the implementation simple and easy to verify.
//
// Parameters:
//   M_DATA_WIDTH – narrow output data width in bits (default 8)
//   RATIO        – number of narrow beats per wide beat (default 4)
//   USER_WIDTH   – sideband user width in bits (default 1)
//   Derived:
//     S_DATA_WIDTH = M_DATA_WIDTH * RATIO
// ==============================================================================

`default_nettype none

module stream_downsizer #(
    parameter int M_DATA_WIDTH = 8,
    parameter int RATIO        = 4,
    parameter int USER_WIDTH   = 1
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset

    // Wide slave (input) interface
    input  logic                            s_valid,
    output logic                            s_ready,
    input  logic [S_DATA_WIDTH-1:0]         s_data,
    input  logic [S_KEEP_WIDTH-1:0]         s_keep,
    input  logic                            s_last,
    input  logic [USER_WIDTH-1:0]           s_user,

    // Narrow master (output) interface
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
    localparam int S_DATA_WIDTH = M_DATA_WIDTH * RATIO;
    localparam int M_KEEP_WIDTH = M_DATA_WIDTH / 8;
    localparam int S_KEEP_WIDTH = S_DATA_WIDTH / 8;
    // Beat counter needs to count 0 … RATIO-1; $clog2(1)=0 is handled
    // naturally since beat_cnt==0 == RATIO-1 when RATIO=1.
    localparam int CNT_WIDTH    = (RATIO > 1) ? $clog2(RATIO) : 1;

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------
    logic [S_DATA_WIDTH-1:0]  latch_data;
    logic [S_KEEP_WIDTH-1:0]  latch_keep;
    logic                     latch_last;
    logic [USER_WIDTH-1:0]    latch_user;
    logic                     latch_valid;

    logic [CNT_WIDTH-1:0]     beat_cnt;

    // -------------------------------------------------------------------------
    // Handshake: accept only when idle
    // -------------------------------------------------------------------------
    assign s_ready = ~latch_valid;
    assign m_valid = latch_valid;

    // -------------------------------------------------------------------------
    // Output slice mux (combinational)
    // -------------------------------------------------------------------------
    assign m_data = latch_data[beat_cnt * M_DATA_WIDTH +: M_DATA_WIDTH];
    assign m_keep = latch_keep[beat_cnt * M_KEEP_WIDTH +: M_KEEP_WIDTH];
    assign m_last = latch_last && (beat_cnt == CNT_WIDTH'(RATIO - 1));
    assign m_user = latch_user;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            latch_data  <= '0;
            latch_keep  <= '0;
            latch_last  <= 1'b0;
            latch_user  <= '0;
            latch_valid <= 1'b0;
            beat_cnt    <= '0;
        end else begin
            // Latch new wide beat when idle
            if (s_valid && s_ready) begin
                latch_data  <= s_data;
                latch_keep  <= s_keep;
                latch_last  <= s_last;
                latch_user  <= s_user;
                latch_valid <= 1'b1;
                beat_cnt    <= '0;
            end

            // Step through narrow beats
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

endmodule

`default_nettype wire
