// ==============================================================================
// File    : stream_rate_matcher.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Clock-domain-crossing (CDC) rate matcher for ready/valid streams.
//   Bridges a stream from the slave clock domain (s_clk / s_rst_n) to the
//   master clock domain (m_clk / m_rst_n) using a fully-asynchronous,
//   Gray-code-pointer FIFO.
//
//   The async FIFO is implemented inline (no external dependencies):
//     • Dual-port memory array shared between clock domains.
//     • Write pointer (binary + Gray) lives in the write (s_clk) domain.
//     • Read  pointer (binary + Gray) lives in the read  (m_clk) domain.
//     • Two-stage synchronisers transfer Gray-coded pointers across domains.
//     • Full  is detected in the write domain using the synchronised read ptr.
//     • Empty is detected in the read  domain using the synchronised write ptr.
//
//   DEPTH must be a power of two and >= 4 (required by the Gray-code full
//   condition: PTR_WIDTH = log2(DEPTH)+1 must be >= 3 bits so the top-two-
//   bit inversion test is well-formed).
//
//   Reset:
//     Both s_rst_n and m_rst_n are active-low SYNCHRONOUS resets relative to
//     their respective clocks.  Assert both during system reset; they may be
//     released independently once the corresponding clock is stable.
//
// Parameters:
//   DATA_WIDTH  – data bus width in bits (default 8)
//   DEPTH       – FIFO depth in beats; must be power-of-two >= 4 (default 16)
//   USER_WIDTH  – sideband user width in bits (default 1)
//   KEEP_WIDTH  – byte-enable width; should equal DATA_WIDTH/8 (default)
//
// Gray-code full condition (Cummings, SNUG 2002):
//   full when wptr_gray == { ~rptr_gray_sync[MSB:MSB-1],
//                              rptr_gray_sync[MSB-2:0] }
// ==============================================================================

`default_nettype none

module stream_rate_matcher #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16,  // must be power-of-two >= 4
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    // Write (slave) clock domain
    input  logic s_clk,
    input  logic s_rst_n,   // active-low synchronous reset in s_clk domain

    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Read (master) clock domain
    input  logic m_clk,
    input  logic m_rst_n,   // active-low synchronous reset in m_clk domain

    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // Derived parameters
    // -------------------------------------------------------------------------
    localparam int ADDR_WIDTH  = $clog2(DEPTH);   // e.g. 4 for DEPTH=16
    localparam int PTR_WIDTH   = ADDR_WIDTH + 1;  // extra MSB for full/empty
    localparam int BEAT_WIDTH  = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;
    localparam int SYNC_STAGES = 2;

    // -------------------------------------------------------------------------
    // Dual-port memory (shared; written in s_clk, read in m_clk)
    // -------------------------------------------------------------------------
    (* ram_style = "distributed" *)
    logic [BEAT_WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Gray-code helper functions
    // -------------------------------------------------------------------------
    function automatic logic [PTR_WIDTH-1:0] bin2gray (
        input logic [PTR_WIDTH-1:0] b
    );
        bin2gray = b ^ (b >> 1);
    endfunction

    // =========================================================================
    // WRITE DOMAIN  (s_clk)
    // =========================================================================

    logic [PTR_WIDTH-1:0] wptr_bin;         // binary write pointer
    logic [PTR_WIDTH-1:0] wptr_gray;        // Gray-coded write pointer

    // Two-stage synchroniser: read Gray pointer → write domain
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] rptr_gray_sync [0:SYNC_STAGES-1];

    logic w_full;

    // Synchronise rptr_gray into the write clock domain
    always_ff @(posedge s_clk) begin
        if (!s_rst_n) begin
            for (int i = 0; i < SYNC_STAGES; i++) rptr_gray_sync[i] <= '0;
        end else begin
            rptr_gray_sync[0] <= rptr_gray;  // rptr_gray driven from m_clk domain
            for (int i = 1; i < SYNC_STAGES; i++) begin
                rptr_gray_sync[i] <= rptr_gray_sync[i-1];
            end
        end
    end

    // Full detection (Cummings SNUG 2002):
    //   FIFO is full when the write pointer is exactly DEPTH entries ahead of
    //   the synchronised read pointer in Gray code space.  This is true when
    //   the top two bits are complemented and all lower bits match.
    assign w_full =
        (wptr_gray[PTR_WIDTH-1]   != rptr_gray_sync[SYNC_STAGES-1][PTR_WIDTH-1]) &&
        (wptr_gray[PTR_WIDTH-2]   != rptr_gray_sync[SYNC_STAGES-1][PTR_WIDTH-2]) &&
        (wptr_gray[PTR_WIDTH-3:0] == rptr_gray_sync[SYNC_STAGES-1][PTR_WIDTH-3:0]);

    assign s_ready = ~w_full;

    always_ff @(posedge s_clk) begin
        if (!s_rst_n) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
        end else if (s_valid && s_ready) begin
            mem[wptr_bin[ADDR_WIDTH-1:0]] <= {s_user, s_last, s_keep, s_data};
            wptr_bin  <= wptr_bin  + 1'b1;
            wptr_gray <= bin2gray(wptr_bin + 1'b1);
        end
    end

    // =========================================================================
    // READ DOMAIN  (m_clk)
    // =========================================================================

    logic [PTR_WIDTH-1:0] rptr_bin;         // binary read pointer
    logic [PTR_WIDTH-1:0] rptr_gray;        // Gray-coded read pointer

    // Two-stage synchroniser: write Gray pointer → read domain
    (* ASYNC_REG = "TRUE" *)
    logic [PTR_WIDTH-1:0] wptr_gray_sync [0:SYNC_STAGES-1];

    logic m_empty;

    // Synchronise wptr_gray into the read clock domain
    always_ff @(posedge m_clk) begin
        if (!m_rst_n) begin
            for (int i = 0; i < SYNC_STAGES; i++) wptr_gray_sync[i] <= '0;
        end else begin
            wptr_gray_sync[0] <= wptr_gray;  // wptr_gray driven from s_clk domain
            for (int i = 1; i < SYNC_STAGES; i++) begin
                wptr_gray_sync[i] <= wptr_gray_sync[i-1];
            end
        end
    end

    // Empty detection: FIFO is empty when read Gray pointer equals the
    // synchronised write Gray pointer.
    assign m_empty = (rptr_gray == wptr_gray_sync[SYNC_STAGES-1]);
    assign m_valid = ~m_empty;

    // Read output (asynchronous read from memory head)
    logic [BEAT_WIDTH-1:0] rd_beat;
    assign rd_beat = mem[rptr_bin[ADDR_WIDTH-1:0]];
    assign {m_user, m_last, m_keep, m_data} = rd_beat;

    always_ff @(posedge m_clk) begin
        if (!m_rst_n) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
        end else if (m_valid && m_ready) begin
            rptr_bin  <= rptr_bin  + 1'b1;
            rptr_gray <= bin2gray(rptr_bin + 1'b1);
        end
    end

    // -------------------------------------------------------------------------
    // Parameter sanity checks
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (DEPTH < 4)
            $fatal(1, "stream_rate_matcher: DEPTH must be >= 4");
        if ((DEPTH & (DEPTH - 1)) != 0)
            $fatal(1, "stream_rate_matcher: DEPTH must be a power of two");
    end
    // synthesis translate_on

endmodule

`default_nettype wire
