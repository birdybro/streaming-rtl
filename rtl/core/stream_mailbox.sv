// =============================================================================
// Module:      stream_mailbox
// Description: A single-entry mailbox register. Accepts one beat from
//              upstream when the mailbox is empty (m_valid == 0), and
//              forwards it to downstream in the following cycle. Implements
//              single-cycle write-to-read semantics: a beat written on cycle N
//              appears on the master port on cycle N+1.
//
//              This is essentially a 1-deep FIFO with registered output. It is
//              useful as a lightweight decoupling element where only one
//              in-flight transaction needs to be buffered at a time.
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
//   s_ready     - Upstream ready (asserted when mailbox is empty)
//   s_data      - Upstream data
//   s_keep      - Upstream byte enables
//   s_last      - Upstream packet end indicator
//   s_user      - Upstream sideband data
//   m_valid     - Downstream valid (asserted when mailbox is full)
//   m_ready     - Downstream ready
//   m_data      - Downstream data (registered)
//   m_keep      - Downstream byte enables (registered)
//   m_last      - Downstream packet end (registered)
//   m_user      - Downstream sideband data (registered)
//
// Latency:       1 cycle
// Throughput:    1 transfer/cycle when mailbox drains each cycle
// Backpressure:  s_ready deasserts while mailbox is occupied
// Limitations:   1-entry depth; single-clock domain only
// =============================================================================

module stream_mailbox #(
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
    // Mailbox register
    // -------------------------------------------------------------------------
    logic                  box_valid;
    logic [DATA_WIDTH-1:0] box_data;
    logic [KEEP_WIDTH-1:0] box_keep;
    logic                  box_last;
    logic [USER_WIDTH-1:0] box_user;

    // Upstream may write only when the mailbox is empty or being consumed
    assign s_ready = ~box_valid | m_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            box_valid <= 1'b0;
            box_data  <= '0;
            box_keep  <= '0;
            box_last  <= 1'b0;
            box_user  <= '0;
        end else begin
            if (s_valid & s_ready) begin
                // Accept new beat from upstream
                box_valid <= 1'b1;
                box_data  <= s_data;
                box_keep  <= s_keep;
                box_last  <= s_last;
                box_user  <= s_user;
            end else if (m_ready & box_valid) begin
                // Downstream consumed; clear mailbox
                box_valid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign m_valid = box_valid;
    assign m_data  = box_data;
    assign m_keep  = box_keep;
    assign m_last  = box_last;
    assign m_user  = box_user;

endmodule
