// ==============================================================================
// File    : stream_delay_line.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Delays a ready/valid stream by DELAY cycles using an internal synchronous
//   FIFO.  The FIFO depth is rounded up to the nearest power-of-two that is
//   >= DELAY (minimum 2), so the actual observable delay depends on when the
//   downstream asserts m_ready.  At full throughput (m_ready always high) the
//   latency from s_valid to m_valid is exactly FIFO_DEPTH cycles.
//
//   Backpressure is supported:
//     s_ready = ~fifo_full   – upstream stalled when FIFO is full
//     m_valid = ~fifo_empty  – downstream stalled when FIFO is empty
//
//   FIFO implementation:
//     Standard synchronous FIFO with an (ADDR_WIDTH+1)-bit grey-free binary
//     pointer scheme (extra MSB distinguishes full from empty).  FIFO_DEPTH
//     must be a power of two for the pointer arithmetic to work correctly.
//
// Parameters:
//   DATA_WIDTH – data bus width in bits (default 8)
//   DELAY      – minimum pipeline delay in clock cycles (default 4)
//   USER_WIDTH – sideband user width in bits (default 1)
//   KEEP_WIDTH – byte-enable width; should equal DATA_WIDTH/8 (default)
// ==============================================================================

`default_nettype none

module stream_delay_line #(
    parameter int DATA_WIDTH = 8,
    parameter int DELAY      = 4,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset

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
    // FIFO sizing: round DELAY up to the next power-of-two (minimum 2)
    // -------------------------------------------------------------------------
    function automatic int clog2_fn (input int v);
        automatic int result = 0;
        automatic int val    = v - 1;
        while (val > 0) begin val >>= 1; result++; end
        return (result < 1) ? 1 : result;
    endfunction

    localparam int FIFO_DEPTH = 1 << clog2_fn(DELAY < 2 ? 2 : DELAY);
    localparam int ADDR_WIDTH = $clog2(FIFO_DEPTH);
    // Payload: data + keep + last + user
    localparam int BEAT_WIDTH = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;

    // -------------------------------------------------------------------------
    // FIFO storage and pointers
    //   Pointers are (ADDR_WIDTH+1) bits wide; the extra MSB lets us
    //   distinguish full (pointers differ only in MSB) from empty (equal).
    // -------------------------------------------------------------------------
    logic [BEAT_WIDTH-1:0]   mem [0:FIFO_DEPTH-1];
    logic [ADDR_WIDTH:0]     wr_ptr;
    logic [ADDR_WIDTH:0]     rd_ptr;

    logic fifo_full;
    logic fifo_empty;

    assign fifo_full  = (wr_ptr[ADDR_WIDTH]   != rd_ptr[ADDR_WIDTH]) &&
                        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign fifo_empty = (wr_ptr == rd_ptr);

    // -------------------------------------------------------------------------
    // Stream handshake
    // -------------------------------------------------------------------------
    assign s_ready = ~fifo_full;
    assign m_valid = ~fifo_empty;

    // -------------------------------------------------------------------------
    // Read-data output (asynchronous read from FIFO head)
    // -------------------------------------------------------------------------
    logic [BEAT_WIDTH-1:0] rd_beat;
    assign rd_beat = mem[rd_ptr[ADDR_WIDTH-1:0]];

    assign {m_user, m_last, m_keep, m_data} = rd_beat;

    // -------------------------------------------------------------------------
    // FIFO write / read pointers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (s_valid && s_ready) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= {s_user, s_last, s_keep, s_data};
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (m_valid && m_ready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Parameter sanity check
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (DELAY < 1)
            $fatal(1, "stream_delay_line: DELAY must be >= 1");
        if (FIFO_DEPTH < DELAY)
            $fatal(1, "stream_delay_line: FIFO_DEPTH computed incorrectly");
    end
    // synthesis translate_on

endmodule

`default_nettype wire
