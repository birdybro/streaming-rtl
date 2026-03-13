// =============================================================================
// Module:      stream_skid_buffer
// Description: A 2-entry skid buffer that absorbs one cycle of backpressure
//              without stalling the upstream pipeline. Uses an explicit
//              three-state FSM: EMPTY, ONE (primary slot occupied), and TWO
//              (both slots occupied / skid active). Full throughput is
//              maintained; upstream sees at most one stall cycle while the
//              buffer drains from TWO to ONE.
//
//              The data path is fully registered. The ready path transitions
//              are one cycle ahead of actual stall, providing clean timing.
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
//   s_ready     - Upstream ready (registered output)
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
// Latency:       1 cycle (EMPTY→ONE, ONE→ONE with pass-through)
//                2 cycles worst-case when skid slot is used
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  Registered s_ready; deasserts when buffer reaches TWO state
// Limitations:   2-entry maximum depth; single-clock domain only
// =============================================================================

module stream_skid_buffer #(
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
    // FSM state encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        EMPTY = 2'b00,
        ONE   = 2'b01,
        TWO   = 2'b10
    } state_t;

    state_t state, state_next;

    // -------------------------------------------------------------------------
    // Storage: slot A (primary / output) and slot B (skid)
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] slotA_data, slotB_data;
    logic [KEEP_WIDTH-1:0] slotA_keep, slotB_keep;
    logic                  slotA_last, slotB_last;
    logic [USER_WIDTH-1:0] slotA_user, slotB_user;

    logic s_accept;
    logic m_accept;

    assign s_accept = s_valid & s_ready;
    assign m_accept = m_valid & m_ready;

    // -------------------------------------------------------------------------
    // FSM next-state logic
    // -------------------------------------------------------------------------
    always_comb begin
        state_next = state;
        unique case (state)
            EMPTY: begin
                if (s_accept)                    state_next = ONE;
            end
            ONE: begin
                if (s_accept && !m_accept)       state_next = TWO;
                else if (!s_accept && m_accept)  state_next = EMPTY;
                // s_accept && m_accept: stay ONE (simultaneous push/pop)
            end
            TWO: begin
                if (m_accept && !s_accept)       state_next = ONE;
                else if (m_accept && s_accept)   state_next = TWO; // replace skid
                // !m_accept: stay TWO (s_ready is 0, no new accept)
            end
            default: state_next = EMPTY;
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= EMPTY;
        end else begin
            state <= state_next;
        end
    end

    // -------------------------------------------------------------------------
    // s_ready: asserted in EMPTY and ONE states
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_ready <= 1'b1;
        end else begin
            // Deassert when transitioning to TWO, re-assert when leaving TWO
            s_ready <= (state_next != TWO);
        end
    end

    // -------------------------------------------------------------------------
    // Slot A — primary output register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slotA_data <= '0;
            slotA_keep <= '0;
            slotA_last <= 1'b0;
            slotA_user <= '0;
        end else begin
            unique case (state)
                EMPTY: begin
                    if (s_accept) begin
                        slotA_data <= s_data;
                        slotA_keep <= s_keep;
                        slotA_last <= s_last;
                        slotA_user <= s_user;
                    end
                end
                ONE: begin
                    if (m_accept && !s_accept) begin
                        // Slot drains; data becomes don't-care, but clear for debug
                        slotA_data <= '0;
                        slotA_keep <= '0;
                        slotA_last <= 1'b0;
                        slotA_user <= '0;
                    end else if (m_accept && s_accept) begin
                        // Simultaneous push/pop: load new beat directly
                        slotA_data <= s_data;
                        slotA_keep <= s_keep;
                        slotA_last <= s_last;
                        slotA_user <= s_user;
                    end else if (s_accept && !m_accept) begin
                        // Pushing to skid; slotA stays, slotB loaded separately
                    end
                end
                TWO: begin
                    if (m_accept) begin
                        // Promote skid slot to output slot
                        slotA_data <= slotB_data;
                        slotA_keep <= slotB_keep;
                        slotA_last <= slotB_last;
                        slotA_user <= slotB_user;
                    end
                end
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Slot B — skid register; loaded when ONE→TWO transition occurs
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slotB_data <= '0;
            slotB_keep <= '0;
            slotB_last <= 1'b0;
            slotB_user <= '0;
        end else begin
            if (state == ONE && s_accept && !m_accept) begin
                slotB_data <= s_data;
                slotB_keep <= s_keep;
                slotB_last <= s_last;
                slotB_user <= s_user;
            end else if (state == TWO && m_accept && s_accept) begin
                // Downstream consumed slotA (promoted from slotB);
                // accept new upstream beat into slotB
                slotB_data <= s_data;
                slotB_keep <= s_keep;
                slotB_last <= s_last;
                slotB_user <= s_user;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign m_valid = (state == ONE) | (state == TWO);
    assign m_data  = slotA_data;
    assign m_keep  = slotA_keep;
    assign m_last  = slotA_last;
    assign m_user  = slotA_user;

endmodule
