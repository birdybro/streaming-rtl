// =============================================================================
// Module:      stream_last_remover
// Description: Removes (absorbs) the s_last signal from an AXI-Stream.  The
//              downstream m_last output is permanently deasserted, converting
//              a framed stream into a continuous byte stream.  All other
//              signals (data, keep, user, valid, ready) pass through
//              unmodified with zero latency.  No state is required; this
//              module is entirely combinatorial.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload in bits           (default: 8)
//   USER_WIDTH  - Width of sideband user signal           (default: 1)
//   KEEP_WIDTH  - Number of byte-enable keep bits         (default: DATA_WIDTH/8)
//
// Ports:
//   clk         - Clock  (unused; present for interface consistency)
//   rst_n       - Active-low synchronous reset (unused; present for consistency)
//   s_valid     - Upstream valid
//   s_ready     - Upstream ready
//   s_data      - Upstream data
//   s_keep      - Upstream byte enables
//   s_last      - Upstream packet end (absorbed; not forwarded)
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid
//   m_ready     - Downstream ready
//   m_data      - Downstream data (pass-through)
//   m_keep      - Downstream byte enables (pass-through)
//   m_last      - Downstream packet end (always 0)
//   m_user      - Downstream sideband data (pass-through)
//
// Latency:       0 cycles (purely combinatorial)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   m_last is always 0; downstream never sees end-of-frame
// =============================================================================

module stream_last_remover #(
    parameter int DATA_WIDTH = 8,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                    clk,    // unused; for interface consistency
    input  logic                    rst_n,  // unused; for interface consistency

    // Slave interface
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,  // absorbed
    input  logic [USER_WIDTH-1:0]   s_user,

    // Master interface (s_last stripped; m_last always 0)
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // Suppress unused-signal warnings from linters
    // synthesis translate_off
    logic unused_clk_rst;
    assign unused_clk_rst = clk ^ rst_n ^ s_last;
    // synthesis translate_on

    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_user  = s_user;
    assign m_last  = 1'b0;

endmodule
