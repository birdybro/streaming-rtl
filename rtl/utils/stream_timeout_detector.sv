// =============================================================================
// stream_timeout_detector.sv
// =============================================================================
// Description:
//   Detects when a frame has been started (first beat received) but not
//   completed (s_last not seen) within TIMEOUT clock cycles. The stream is
//   passed through unchanged. The timeout output is a level signal that
//   asserts when the counter reaches TIMEOUT and clears when the frame ends
//   or on reset.
//
// Parameters:
//   DATA_WIDTH  - Width of data bus (default: 8)
//   TIMEOUT     - Cycles allowed between frame start and s_last (default: 1000)
//   USER_WIDTH  - Width of user sideband (default: 1)
//   KEEP_WIDTH  - Number of byte-enable bits (default: DATA_WIDTH/8)
//
// Ports:
//   clk/rst_n        - Clock and active-low synchronous reset
//   s_*/m_*          - Stream in/out (zero-latency pass-through)
//   timeout          - Asserts when partial frame exceeds TIMEOUT cycles
//   timeout_cnt      - Current cycle count since frame start
//
// Latency: 0 cycles
// Throughput: 1 beat/cycle
// Backpressure: passes m_ready to s_ready
// =============================================================================

module stream_timeout_detector #(
    parameter int DATA_WIDTH = 8,
    parameter int TIMEOUT    = 1000,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              s_valid,
    output logic                              s_ready,
    input  logic [DATA_WIDTH-1:0]             s_data,
    input  logic [KEEP_WIDTH-1:0]             s_keep,
    input  logic                              s_last,
    input  logic [USER_WIDTH-1:0]             s_user,

    output logic                              m_valid,
    input  logic                              m_ready,
    output logic [DATA_WIDTH-1:0]             m_data,
    output logic [KEEP_WIDTH-1:0]             m_keep,
    output logic                              m_last,
    output logic [USER_WIDTH-1:0]             m_user,

    output logic                              timeout,
    output logic [$clog2(TIMEOUT+1)-1:0]      timeout_cnt
);

    // Pass-through
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    logic in_frame;
    logic [$clog2(TIMEOUT+1)-1:0] cnt;

    assign timeout_cnt = cnt;
    assign timeout     = in_frame && (cnt >= TIMEOUT[$clog2(TIMEOUT+1)-1:0]);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_frame <= 1'b0;
            cnt      <= '0;
        end else begin
            if (s_valid && m_ready) begin
                if (!in_frame) begin
                    // First beat: start counting
                    in_frame <= 1'b1;
                    cnt      <= '0;
                end
                if (s_last) begin
                    // Frame complete
                    in_frame <= 1'b0;
                    cnt      <= '0;
                end
            end else if (in_frame) begin
                if (cnt < TIMEOUT[$clog2(TIMEOUT+1)-1:0]) begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule
