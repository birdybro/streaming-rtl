// =============================================================================
// Module:      stream_frame_detector
// Description: Transparent pass-through that detects start-of-frame (SoF) and
//              end-of-frame (EoF) boundaries in an AXI-Stream.  The sof output
//              pulses for exactly one cycle on the first accepted beat of each
//              new frame.  The eof output pulses for exactly one cycle on the
//              accepted beat where s_last is asserted.  Both pulses are
//              coincident with the accepted transfer (s_valid & m_ready).
//              All data signals pass through unmodified with zero latency.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload in bits           (default: 8)
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
//   s_last      - Upstream packet end
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid
//   m_ready     - Downstream ready
//   m_data      - Downstream data (pass-through)
//   m_keep      - Downstream byte enables (pass-through)
//   m_last      - Downstream packet end (pass-through)
//   m_user      - Downstream sideband data (pass-through)
//   sof         - Start-of-frame pulse (coincident with first beat of frame)
//   eof         - End-of-frame pulse (coincident with s_last beat)
//
// Latency:       0 cycles (combinatorial pass-through)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready follows m_ready directly
// Limitations:   Single-clock domain only
// =============================================================================

module stream_frame_detector #(
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

    // Master interface (pass-through)
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user,

    // Frame boundary indicators
    output logic                    sof,    // pulses on first beat of each frame
    output logic                    eof     // pulses on last beat of each frame
);

    // -------------------------------------------------------------------------
    // Track whether the next accepted beat is a start-of-frame.
    // Initialises to 1 so the very first beat after reset is flagged as SoF.
    // Set again whenever the previous beat was an EoF.
    // -------------------------------------------------------------------------
    logic at_sof;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            at_sof <= 1'b1;
        end else if (s_valid && m_ready) begin
            // After last beat, next accepted beat starts a new frame
            at_sof <= s_last;
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

    // sof/eof coincident with the accepted transfer
    assign sof = s_valid && m_ready && at_sof;
    assign eof = s_valid && m_ready && s_last;

endmodule
