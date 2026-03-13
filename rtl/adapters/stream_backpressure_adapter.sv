// ==============================================================================
// File    : stream_backpressure_adapter.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Handles backpressure mismatches between sources and sinks using an
//   internal synchronous FIFO, with two selectable operating modes:
//
//   MODE = "ABSORB" (default):
//     A normal FIFO-backed buffer.  The upstream is stalled (s_ready=0)
//     when the FIFO is full.  Use when the downstream may temporarily
//     deassert m_ready and the upstream must not drop data.
//
//   MODE = "DROP":
//     The upstream is never stalled (s_ready=1 always).  Incoming beats
//     are written to the FIFO only when it is not full; if the FIFO is
//     full the beat is silently discarded and the 'dropped' output is
//     pulsed high for one cycle.
//
//   FIFO implementation:
//     Synchronous, single-clock, power-of-two depth (must be >= 2).
//     Pointer scheme: (ADDR_WIDTH+1)-bit binary counters; full/empty
//     detected by comparing the extra MSB and the lower address bits.
//
// Parameters:
//   DATA_WIDTH – data bus width in bits (default 8)
//   DEPTH      – FIFO depth in beats; must be a power of two >= 2 (default 16)
//   USER_WIDTH – sideband user width in bits (default 1)
//   KEEP_WIDTH – byte-enable width; should equal DATA_WIDTH/8 (default)
//   MODE       – "ABSORB" or "DROP" (default "ABSORB")
//
// Ports:
//   dropped    – one-cycle pulse per dropped beat (MODE="DROP" only, else 0)
// ==============================================================================

`default_nettype none

module stream_backpressure_adapter #(
    parameter int          DATA_WIDTH = 8,
    parameter int          DEPTH      = 16,
    parameter int          USER_WIDTH = 1,
    parameter int          KEEP_WIDTH = DATA_WIDTH / 8,
    parameter string       MODE       = "ABSORB"
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
    output logic [USER_WIDTH-1:0]   m_user,

    // Drop indicator (pulses high for one cycle on each dropped beat)
    output logic                    dropped
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int BEAT_WIDTH = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;

    // -------------------------------------------------------------------------
    // FIFO storage and pointers
    // -------------------------------------------------------------------------
    logic [BEAT_WIDTH-1:0]  mem [0:DEPTH-1];
    logic [ADDR_WIDTH:0]    wr_ptr;
    logic [ADDR_WIDTH:0]    rd_ptr;

    logic fifo_full;
    logic fifo_empty;

    assign fifo_full  = (wr_ptr[ADDR_WIDTH]    != rd_ptr[ADDR_WIDTH]) &&
                        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign fifo_empty = (wr_ptr == rd_ptr);

    // -------------------------------------------------------------------------
    // Derived constants from MODE parameter
    // -------------------------------------------------------------------------
    localparam logic MODE_IS_DROP = (MODE == "DROP");

    // -------------------------------------------------------------------------
    // Handshake
    //   ABSORB: stall upstream when full
    //   DROP  : always accept; discard silently when full
    // -------------------------------------------------------------------------
    assign s_ready = MODE_IS_DROP ? 1'b1 : ~fifo_full;
    assign m_valid = ~fifo_empty;

    // -------------------------------------------------------------------------
    // Drop flag: valid beat arrived but FIFO was full (DROP mode only)
    // -------------------------------------------------------------------------
    assign dropped = MODE_IS_DROP & s_valid & fifo_full;

    // -------------------------------------------------------------------------
    // Write: only when not full (in DROP mode this silently discards)
    // -------------------------------------------------------------------------
    // Read output (asynchronous FIFO head)
    // -------------------------------------------------------------------------
    logic [BEAT_WIDTH-1:0] rd_beat;
    assign rd_beat = mem[rd_ptr[ADDR_WIDTH-1:0]];
    assign {m_user, m_last, m_keep, m_data} = rd_beat;

    // -------------------------------------------------------------------------
    // FIFO pointer update
    //   Write when valid and not full (DROP mode always accepts; ABSORB only
    //   when not full since s_ready guarantees back-pressure).
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (s_valid && ~fifo_full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= {s_user, s_last, s_keep, s_data};
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (m_valid && m_ready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Parameter sanity checks
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
            $fatal(1, "stream_backpressure_adapter: DEPTH must be a power of two >= 2");
        if (MODE != "ABSORB" && MODE != "DROP")
            $fatal(1, "stream_backpressure_adapter: MODE must be \"ABSORB\" or \"DROP\"");
    end
    // synthesis translate_on

endmodule

`default_nettype wire
