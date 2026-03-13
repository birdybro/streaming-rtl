// =============================================================================
// Module:      stream_pipeline_stage
// Description: A lightweight single-stage pipeline register for the stream
//              data path. The data path is fully registered (zero combinational
//              logic between s_data and m_data). The ready path is
//              combinational: s_ready is asserted whenever downstream is ready
//              or the output register is empty, enabling zero-bubble operation
//              at the cost of a combinational ready path.
//
//              Use this module when latency is acceptable but clock frequency
//              benefit of a registered data path is desired. For fully
//              registered backpressure, use stream_register_slice instead.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload in bits         (default: 8)
//   USER_WIDTH  - Width of sideband user signal         (default: 1)
//   KEEP_WIDTH  - Number of byte-enable keep bits       (default: DATA_WIDTH/8)
//
// Ports:
//   clk         - Clock
//   rst_n       - Active-low synchronous reset
//   s_valid     - Upstream valid
//   s_ready     - Upstream ready (combinational: m_ready | ~m_valid)
//   s_data      - Upstream data
//   s_keep      - Upstream byte enables
//   s_last      - Upstream packet end indicator
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid (registered output)
//   m_ready     - Downstream ready (backpressure input)
//   m_data      - Downstream data (registered output)
//   m_keep      - Downstream byte enables (registered output)
//   m_last      - Downstream packet end (registered output)
//   m_user      - Downstream sideband data (registered output)
//
// Latency:       1 cycle
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  Combinational ready path (s_ready = m_ready | ~m_valid)
// Limitations:   Ready path is combinational; may create long timing paths.
//                Not suitable for CDC; single-clock domain only.
// =============================================================================

module stream_pipeline_stage #(
    parameter int DATA_WIDTH = 8,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Upstream (slave) interface
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Downstream (master) interface
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // Combinational ready: upstream may push whenever the output register is
    // empty or downstream is consuming this cycle.
    // -------------------------------------------------------------------------
    assign s_ready = m_ready | ~m_valid;

    // -------------------------------------------------------------------------
    // Output register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
            m_data  <= '0;
            m_keep  <= '0;
            m_last  <= 1'b0;
            m_user  <= '0;
        end else begin
            if (s_ready) begin
                // Output register is free to accept a new beat
                m_valid <= s_valid;
                if (s_valid) begin
                    m_data <= s_data;
                    m_keep <= s_keep;
                    m_last <= s_last;
                    m_user <= s_user;
                end
            end
            // If !s_ready (downstream stalled), hold current output unchanged
        end
    end

endmodule
