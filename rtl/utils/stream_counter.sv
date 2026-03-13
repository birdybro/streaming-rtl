// =============================================================================
// stream_counter.sv
// =============================================================================
// Description:
//   Counts valid transactions passing through the stream. Can be configured to
//   count every valid beat or only end-of-frame beats (s_last asserted).
//   The stream is passed through unmodified (zero-latency).
//
// Parameters:
//   DATA_WIDTH   - Width of data bus (default: 8)
//   COUNT_WIDTH  - Width of count register (default: 32)
//   USER_WIDTH   - Width of user sideband (default: 1)
//   KEEP_WIDTH   - Number of byte-enable bits (default: DATA_WIDTH/8)
//   COUNT_FRAMES - 1: count frames (last beats only); 0: count all beats
//
// Ports:
//   clk         - Clock
//   rst_n       - Active-low synchronous reset
//   s_valid/ready/data/keep/last/user - Input stream
//   m_valid/ready/data/keep/last/user - Output stream (pass-through)
//   count       - Running counter value
//   count_clear - Synchronous clear for counter
//
// Latency: 0 cycles (combinational pass-through)
// Throughput: 1 beat/cycle
// Backpressure: fully supported (passes m_ready back to s_ready)
// =============================================================================

module stream_counter #(
    parameter int DATA_WIDTH   = 8,
    parameter int COUNT_WIDTH  = 32,
    parameter int USER_WIDTH   = 1,
    parameter int KEEP_WIDTH   = DATA_WIDTH / 8,
    parameter bit COUNT_FRAMES = 1'b1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user,

    output logic [COUNT_WIDTH-1:0]  count,
    input  logic                    count_clear
);

    // Pass-through
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    // Count logic
    logic beat_en;
    always_comb begin
        if (COUNT_FRAMES)
            beat_en = s_valid & m_ready & s_last;
        else
            beat_en = s_valid & m_ready;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= '0;
        end else if (count_clear) begin
            count <= '0;
        end else if (beat_en) begin
            count <= count + 1'b1;
        end
    end

endmodule
