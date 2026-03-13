// =============================================================================
// Module:      stream_last_inserter
// Description: Inserts m_last into a continuous AXI-Stream based on two
//              independent mechanisms:
//                1. Periodic: every COUNT_BEATS accepted beats m_last is
//                   asserted automatically (same behaviour as packetizer).
//                2. Sideband override: when insert_last is held high on a
//                   cycle with a valid accepted beat, m_last is forced high
//                   regardless of the beat counter.
//              Both mechanisms reset the beat counter, so either source of
//              last starts a fresh COUNT_BEATS interval.  s_last is not
//              required as an input; the module generates all framing.
//              All data signals pass through unmodified with zero latency.
//
// Parameters:
//   DATA_WIDTH   - Width of data payload in bits           (default: 8)
//   COUNT_BEATS  - Beats per interval for periodic last    (default: 64)
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
//   s_user       - Upstream sideband data
//   insert_last  - Sideband override: forces m_last on current valid beat
//   m_valid      - Downstream valid
//   m_ready      - Downstream ready
//   m_data       - Downstream data
//   m_keep       - Downstream byte enables
//   m_last       - Downstream packet end (periodic or sideband-forced)
//   m_user       - Downstream sideband data
//
// Latency:       0 cycles (combinatorial pass-through)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   COUNT_BEATS >= 1; s_last not used as input
// =============================================================================

module stream_last_inserter #(
    parameter int DATA_WIDTH  = 8,
    parameter int COUNT_BEATS = 64,
    parameter int USER_WIDTH  = 1,
    parameter int KEEP_WIDTH  = DATA_WIDTH / 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Slave interface (no s_last - continuous stream)
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Sideband: force last on the current valid beat
    input  logic                    insert_last,

    // Master interface
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // synthesis translate_off
    initial begin
        if (COUNT_BEATS < 1)
            $fatal(1, "stream_last_inserter: COUNT_BEATS must be >= 1, got %0d", COUNT_BEATS);
    end
    // synthesis translate_on

    localparam int CNT_W = (COUNT_BEATS > 1) ? $clog2(COUNT_BEATS) : 1;

    // -------------------------------------------------------------------------
    // Beat counter: 0-indexed; resets on any m_last transfer
    // -------------------------------------------------------------------------
    logic [CNT_W-1:0] beat_count;
    logic             force_last;

    assign force_last = (beat_count == CNT_W'(COUNT_BEATS - 1)) || insert_last;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            beat_count <= '0;
        end else if (s_valid && m_ready) begin
            if (force_last)
                beat_count <= '0;
            else
                beat_count <= beat_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial pass-through; m_last generated from counter or sideband
    // -------------------------------------------------------------------------
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_user  = s_user;
    assign m_last  = force_last;

endmodule
