// =============================================================================
// Module:      stream_packetizer
// Description: Accepts a continuous byte stream (no s_last input) and frames
//              it into fixed-size packets by asserting m_last on every
//              PACKET_LEN-th accepted beat.  The module is a zero-latency
//              combinatorial pass-through; only the internal beat counter is
//              registered.  All data, keep, and user signals are passed
//              unmodified from slave to master.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload in bits           (default: 8)
//   PACKET_LEN  - Number of beats per output packet       (default: 64)
//   USER_WIDTH  - Width of sideband user signal           (default: 1)
//   KEEP_WIDTH  - Number of byte-enable keep bits         (default: DATA_WIDTH/8)
//
// Ports:
//   clk         - Clock
//   rst_n       - Active-low synchronous reset
//   s_valid     - Upstream valid
//   s_ready     - Upstream ready
//   s_data      - Upstream data
//   s_keep      - Upstream byte enables
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid
//   m_ready     - Downstream ready
//   m_data      - Downstream data
//   m_keep      - Downstream byte enables
//   m_last      - Downstream packet end (asserted every PACKET_LEN beats)
//   m_user      - Downstream sideband data
//
// Latency:       0 cycles (combinatorial pass-through)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   PACKET_LEN >= 1; s_last not used as input
// =============================================================================

module stream_packetizer #(
    parameter int DATA_WIDTH = 8,
    parameter int PACKET_LEN = 64,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Slave interface (continuous stream, no s_last)
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Master interface (framed packets)
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // synthesis translate_off
    initial begin
        if (PACKET_LEN < 1)
            $fatal(1, "stream_packetizer: PACKET_LEN must be >= 1, got %0d", PACKET_LEN);
    end
    // synthesis translate_on

    localparam int CNT_W = (PACKET_LEN > 1) ? $clog2(PACKET_LEN) : 1;

    // -------------------------------------------------------------------------
    // Beat counter: 0-indexed, wraps at PACKET_LEN-1
    // -------------------------------------------------------------------------
    logic [CNT_W-1:0] beat_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            beat_count <= '0;
        end else if (s_valid && m_ready) begin
            if (beat_count == CNT_W'(PACKET_LEN - 1))
                beat_count <= '0;
            else
                beat_count <= beat_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial pass-through; m_last generated from counter
    // -------------------------------------------------------------------------
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_user  = s_user;
    assign m_last  = (beat_count == CNT_W'(PACKET_LEN - 1));

endmodule
