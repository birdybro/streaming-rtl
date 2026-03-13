// =============================================================================
// Module:      stream_register_slice
// Description: A register slice that fully breaks the combinational path
//              between upstream (slave) and downstream (master) interfaces.
//              Uses a skid (double-register) approach with two internal slots.
//              When the primary slot is full and downstream is not ready, the
//              incoming transaction is held in the skid slot and upstream is
//              stalled. This ensures both the data path and the backpressure
//              (ready) path are fully registered, eliminating any combinational
//              dependency between s_ready and m_valid/m_ready.
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
//   s_ready     - Upstream ready (backpressure, registered output)
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
// Latency:       1 cycle minimum, 2 cycles when skid slot is in use
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  Fully registered; s_ready deasserts one cycle before stall
// Limitations:   Not suitable for CDC; single-clock domain only
// =============================================================================

module stream_register_slice #(
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
    // Primary output register (slot 0)
    // -------------------------------------------------------------------------
    logic                  slot0_valid;
    logic [DATA_WIDTH-1:0] slot0_data;
    logic [KEEP_WIDTH-1:0] slot0_keep;
    logic                  slot0_last;
    logic [USER_WIDTH-1:0] slot0_user;

    // -------------------------------------------------------------------------
    // Skid register (slot 1) — holds data when slot0 is full and downstream
    // is not ready, allowing s_ready to be deasserted one cycle early.
    // -------------------------------------------------------------------------
    logic                  slot1_valid;
    logic [DATA_WIDTH-1:0] slot1_data;
    logic [KEEP_WIDTH-1:0] slot1_keep;
    logic                  slot1_last;
    logic [USER_WIDTH-1:0] slot1_user;

    // s_ready is registered: upstream may accept a beat only when slot1 is empty
    logic s_ready_r;

    // Combinational accept signals
    logic s_accept;  // beat accepted from upstream this cycle
    logic m_accept;  // beat accepted by downstream this cycle

    assign s_accept = s_valid & s_ready_r;
    assign m_accept = m_valid & m_ready;

    // -------------------------------------------------------------------------
    // s_ready register: deassert when slot1 becomes valid
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_ready_r <= 1'b1;
        end else begin
            // Deassert ready when we are about to fill the skid slot
            // (slot0 is full, downstream is not accepting, and upstream has data)
            if (slot0_valid && !m_accept && s_accept) begin
                s_ready_r <= 1'b0;
            end else if (!slot1_valid || m_accept) begin
                // Re-assert when skid slot drains
                s_ready_r <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Slot 0 — primary output register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slot0_valid <= 1'b0;
            slot0_data  <= '0;
            slot0_keep  <= '0;
            slot0_last  <= 1'b0;
            slot0_user  <= '0;
        end else begin
            if (m_accept) begin
                // Downstream consumed slot0; promote skid or accept new input
                if (slot1_valid) begin
                    slot0_valid <= 1'b1;
                    slot0_data  <= slot1_data;
                    slot0_keep  <= slot1_keep;
                    slot0_last  <= slot1_last;
                    slot0_user  <= slot1_user;
                end else if (s_accept) begin
                    slot0_valid <= 1'b1;
                    slot0_data  <= s_data;
                    slot0_keep  <= s_keep;
                    slot0_last  <= s_last;
                    slot0_user  <= s_user;
                end else begin
                    slot0_valid <= 1'b0;
                end
            end else if (!slot0_valid && s_accept) begin
                // Slot0 was empty; load directly from upstream
                slot0_valid <= 1'b1;
                slot0_data  <= s_data;
                slot0_keep  <= s_keep;
                slot0_last  <= s_last;
                slot0_user  <= s_user;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Slot 1 — skid register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slot1_valid <= 1'b0;
            slot1_data  <= '0;
            slot1_keep  <= '0;
            slot1_last  <= 1'b0;
            slot1_user  <= '0;
        end else begin
            if (m_accept && slot1_valid) begin
                // Slot1 was promoted to slot0; clear skid
                slot1_valid <= 1'b0;
            end else if (slot0_valid && !m_accept && s_accept) begin
                // Slot0 full and downstream stalled; push to skid
                slot1_valid <= 1'b1;
                slot1_data  <= s_data;
                slot1_keep  <= s_keep;
                slot1_last  <= s_last;
                slot1_user  <= s_user;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign s_ready = s_ready_r;
    assign m_valid = slot0_valid;
    assign m_data  = slot0_data;
    assign m_keep  = slot0_keep;
    assign m_last  = slot0_last;
    assign m_user  = slot0_user;

endmodule
