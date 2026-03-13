// =============================================================================
// stream_perf_monitor.sv
// =============================================================================
// Description:
//   Non-intrusive performance monitor for a streaming bus. Accumulates five
//   statistics counters while passing the stream through unchanged:
//     beat_count  - number of accepted beats (valid & ready)
//     byte_count  - number of valid bytes (popcount of keep per beat)
//     cycle_count - total elapsed clock cycles since last clear
//     idle_cycles - cycles where valid=0 (source not producing)
//     bp_cycles   - cycles where valid=1 but ready=0 (back-pressure)
//
// Parameters:
//   DATA_WIDTH  - Width of data bus (default: 8)
//   STAT_WIDTH  - Width of statistic counters (default: 32)
//   USER_WIDTH  - Width of user sideband (default: 1)
//   KEEP_WIDTH  - Number of byte-enable bits (default: DATA_WIDTH/8)
//
// Ports:
//   clk/rst_n              - Clock and active-low synchronous reset
//   s_*/m_*                - Stream in/out (zero-latency pass-through)
//   stats_clear            - Synchronous clear for all counters
//   beat_count             - Accepted beats
//   byte_count             - Valid bytes transferred
//   cycle_count            - Total cycles measured
//   idle_cycles            - Cycles with s_valid=0
//   bp_cycles              - Cycles with s_valid=1 and m_ready=0
//
// Latency: 0 cycles
// Throughput: 1 beat/cycle
// Backpressure: passes m_ready directly to s_ready
// =============================================================================

module stream_perf_monitor #(
    parameter int DATA_WIDTH = 8,
    parameter int STAT_WIDTH = 32,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   s_valid,
    output logic                   s_ready,
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic [KEEP_WIDTH-1:0]  s_keep,
    input  logic                   s_last,
    input  logic [USER_WIDTH-1:0]  s_user,

    output logic                   m_valid,
    input  logic                   m_ready,
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic [KEEP_WIDTH-1:0]  m_keep,
    output logic                   m_last,
    output logic [USER_WIDTH-1:0]  m_user,

    input  logic                   stats_clear,
    output logic [STAT_WIDTH-1:0]  beat_count,
    output logic [STAT_WIDTH-1:0]  byte_count,
    output logic [STAT_WIDTH-1:0]  cycle_count,
    output logic [STAT_WIDTH-1:0]  idle_cycles,
    output logic [STAT_WIDTH-1:0]  bp_cycles
);

    // Pass-through
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    // Popcount of keep
    logic [STAT_WIDTH-1:0] keep_ones;
    always_comb begin
        keep_ones = '0;
        for (int i = 0; i < KEEP_WIDTH; i++) begin
            keep_ones = keep_ones + {{(STAT_WIDTH-1){1'b0}}, s_keep[i]};
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n || stats_clear) begin
            beat_count  <= '0;
            byte_count  <= '0;
            cycle_count <= '0;
            idle_cycles <= '0;
            bp_cycles   <= '0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
            if (s_valid && m_ready) begin
                beat_count <= beat_count + 1'b1;
                byte_count <= byte_count + keep_ones;
            end
            if (!s_valid) begin
                idle_cycles <= idle_cycles + 1'b1;
            end
            if (s_valid && !m_ready) begin
                bp_cycles <= bp_cycles + 1'b1;
            end
        end
    end

endmodule
