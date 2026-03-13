// =============================================================================
// Module:      stream_frame_length_counter
// Description: Transparent pass-through that counts the number of beats in
//              each incoming frame and exposes that count on the count output.
//              The count value is valid (reflects the completed frame length)
//              on the cycle that m_last is asserted.  Between end-of-frame
//              events the count output shows the running beat index within the
//              current frame (1-indexed).  All data signals pass through
//              unmodified with zero latency.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload in bits            (default: 8)
//   MAX_LEN     - Maximum supported frame length in beats  (default: 4096)
//   USER_WIDTH  - Width of sideband user signal            (default: 1)
//   KEEP_WIDTH  - Number of byte-enable keep bits          (default: DATA_WIDTH/8)
//
// Ports:
//   clk         - Clock
//   rst_n       - Active-low synchronous reset
//   s_valid     - Upstream valid
//   s_ready     - Upstream ready
//   s_data      - Upstream data
//   s_keep      - Upstream byte enables
//   s_last      - Upstream packet end
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid
//   m_ready     - Downstream ready
//   m_data      - Downstream data (pass-through)
//   m_keep      - Downstream byte enables (pass-through)
//   m_last      - Downstream packet end (pass-through)
//   m_user      - Downstream sideband data (pass-through)
//   count       - Current beat count; frame length valid when m_last asserted
//
// Latency:       0 cycles (combinatorial pass-through)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   Frames longer than MAX_LEN beats will cause counter wrap
// =============================================================================

module stream_frame_length_counter #(
    parameter int DATA_WIDTH = 8,
    parameter int MAX_LEN    = 4096,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // Slave interface
    input  logic                            s_valid,
    output logic                            s_ready,
    input  logic [DATA_WIDTH-1:0]           s_data,
    input  logic [KEEP_WIDTH-1:0]           s_keep,
    input  logic                            s_last,
    input  logic [USER_WIDTH-1:0]           s_user,

    // Master interface (pass-through)
    output logic                            m_valid,
    input  logic                            m_ready,
    output logic [DATA_WIDTH-1:0]           m_data,
    output logic [KEEP_WIDTH-1:0]           m_keep,
    output logic                            m_last,
    output logic [USER_WIDTH-1:0]           m_user,

    // Frame length: 1-indexed beat count, valid when m_last is asserted
    output logic [$clog2(MAX_LEN+1)-1:0]   count
);

    localparam int CNT_W = $clog2(MAX_LEN + 1);

    // -------------------------------------------------------------------------
    // Beat counter: 1-indexed; resets to 1 after each end-of-frame
    // -------------------------------------------------------------------------
    logic [CNT_W-1:0] beat_count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            beat_count <= CNT_W'(1);
        end else if (s_valid && m_ready) begin
            if (s_last || beat_count == CNT_W'(MAX_LEN))
                beat_count <= CNT_W'(1);
            else
                beat_count <= beat_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial pass-through
    // -------------------------------------------------------------------------
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    // count is the running 1-indexed beat position; equals frame length at EoF
    assign count   = beat_count;

endmodule
