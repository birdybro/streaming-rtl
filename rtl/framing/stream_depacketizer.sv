// =============================================================================
// Module:      stream_depacketizer
// Description: Strips framing from a framed AXI-Stream by absorbing the s_last
//              signal.  The output m_last is always deasserted, yielding a
//              continuous data stream regardless of upstream framing boundaries.
//              All data, keep, and user signals are passed through unmodified.
//              A frame_count register increments each time a complete upstream
//              frame is received (s_last fires on an accepted beat).
//
// Parameters:
//   DATA_WIDTH   - Width of data payload in bits           (default: 8)
//   USER_WIDTH   - Width of sideband user signal           (default: 1)
//   KEEP_WIDTH   - Number of byte-enable keep bits         (default: DATA_WIDTH/8)
//
// Ports:
//   clk          - Clock
//   rst_n        - Active-low synchronous reset
//   s_valid      - Upstream valid
//   s_ready      - Upstream ready
//   s_data       - Upstream data
//   s_keep       - Upstream byte enables
//   s_last       - Upstream packet end (absorbed; not forwarded)
//   s_user       - Upstream sideband data
//   m_valid      - Downstream valid
//   m_ready      - Downstream ready
//   m_data       - Downstream data
//   m_keep       - Downstream byte enables
//   m_last       - Downstream packet end (always 0)
//   m_user       - Downstream sideband data
//   frame_count  - Running count of completed upstream frames (32-bit)
//
// Latency:       0 cycles (combinatorial pass-through)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   frame_count wraps at 2^32; m_last is always 0
// =============================================================================

module stream_depacketizer #(
    parameter int DATA_WIDTH = 8,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Slave interface
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Master interface (continuous stream; m_last always 0)
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user,

    // Frame counter
    output logic [31:0]             frame_count
);

    // -------------------------------------------------------------------------
    // Frame counter: increments on each upstream end-of-frame
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            frame_count <= '0;
        end else if (s_valid && m_ready && s_last) begin
            frame_count <= frame_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial pass-through; s_last absorbed (m_last tied to 0)
    // -------------------------------------------------------------------------
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_user  = s_user;
    assign m_last  = 1'b0;

endmodule
