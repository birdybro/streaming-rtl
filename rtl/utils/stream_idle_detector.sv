// =============================================================================
// stream_idle_detector.sv
// =============================================================================
// Description:
//   Detects when a stream has been idle (no accepted transactions) for more
//   than TIMEOUT clock cycles. The stream is passed through unchanged.
//   The idle output is a level signal: it asserts when the idle counter
//   reaches TIMEOUT and de-asserts as soon as a new transaction appears.
//
// Parameters:
//   DATA_WIDTH  - Width of data bus (default: 8)
//   TIMEOUT     - Number of idle cycles before asserting idle (default: 100)
//   USER_WIDTH  - Width of user sideband (default: 1)
//   KEEP_WIDTH  - Number of byte-enable bits (default: DATA_WIDTH/8)
//
// Ports:
//   clk/rst_n        - Clock and active-low synchronous reset
//   s_*/m_*          - Stream in/out (zero-latency pass-through)
//   idle             - Asserts after TIMEOUT consecutive idle cycles
//   idle_cycles      - Current idle cycle count
//
// Latency: 0 cycles
// Throughput: 1 beat/cycle
// Backpressure: passes m_ready to s_ready
// =============================================================================

module stream_idle_detector #(
    parameter int DATA_WIDTH = 8,
    parameter int TIMEOUT    = 100,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                             clk,
    input  logic                             rst_n,

    input  logic                             s_valid,
    output logic                             s_ready,
    input  logic [DATA_WIDTH-1:0]            s_data,
    input  logic [KEEP_WIDTH-1:0]            s_keep,
    input  logic                             s_last,
    input  logic [USER_WIDTH-1:0]            s_user,

    output logic                             m_valid,
    input  logic                             m_ready,
    output logic [DATA_WIDTH-1:0]            m_data,
    output logic [KEEP_WIDTH-1:0]            m_keep,
    output logic                             m_last,
    output logic [USER_WIDTH-1:0]            m_user,

    output logic                             idle,
    output logic [$clog2(TIMEOUT+1)-1:0]     idle_cycles
);

    // Pass-through
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    logic [$clog2(TIMEOUT+1)-1:0] cnt;
    assign idle_cycles = cnt;
    assign idle        = (cnt >= TIMEOUT[$clog2(TIMEOUT+1)-1:0]);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt <= '0;
        end else begin
            if (s_valid && m_ready) begin
                cnt <= '0;
            end else if (cnt < TIMEOUT[$clog2(TIMEOUT+1)-1:0]) begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule
