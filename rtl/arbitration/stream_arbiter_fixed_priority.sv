// =============================================================================
// Module:       stream_arbiter_fixed_priority
// Library:      streaming-rtl
// Description:  N-input fixed-priority AXI-Stream arbiter. Input 0 has the
//               highest priority. Once a frame begins (valid asserted without
//               last), the grant is held for the duration of the frame to
//               prevent mid-frame switching. A new arbitration decision is
//               made only when the bus is idle or the current frame ends.
//
// Parameters:
//   NUM_INPUTS  - Number of stream inputs (default 4)
//   DATA_WIDTH  - Payload data width in bits (default 8)
//   USER_WIDTH  - User sideband width in bits (default 1)
//   KEEP_WIDTH  - Byte-enable width (default DATA_WIDTH/8)
//
// Interface:    AXI4-Stream (ready/valid/last/keep/user)
//
// Reset:        Synchronous active-low (rst_n)
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module stream_arbiter_fixed_priority #(
    parameter int unsigned NUM_INPUTS  = 4,
    parameter int unsigned DATA_WIDTH  = 8,
    parameter int unsigned USER_WIDTH  = 1,
    parameter int unsigned KEEP_WIDTH  = DATA_WIDTH / 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // Slave ports (inputs)
    input  logic [NUM_INPUTS-1:0]                    s_valid,
    output logic [NUM_INPUTS-1:0]                    s_ready,
    input  logic [NUM_INPUTS-1:0][DATA_WIDTH-1:0]    s_data,
    input  logic [NUM_INPUTS-1:0][KEEP_WIDTH-1:0]    s_keep,
    input  logic [NUM_INPUTS-1:0]                    s_last,
    input  logic [NUM_INPUTS-1:0][USER_WIDTH-1:0]    s_user,

    // Master port (output)
    output logic                                     m_valid,
    input  logic                                     m_ready,
    output logic [DATA_WIDTH-1:0]                    m_data,
    output logic [KEEP_WIDTH-1:0]                    m_keep,
    output logic                                     m_last,
    output logic [USER_WIDTH-1:0]                    m_user,

    // Current grant (one-hot)
    output logic [NUM_INPUTS-1:0]                    grant
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic [$clog2(NUM_INPUTS)-1:0] grant_idx;     // binary index of active grant
    logic                          grant_valid;    // a grant is currently active
    logic                          frame_active;   // mid-frame lock
    logic                          beat_accepted;  // handshake this cycle

    // Next-arbitration combinational result
    logic [$clog2(NUM_INPUTS)-1:0] next_grant_idx;
    logic                          next_grant_found;

    // -------------------------------------------------------------------------
    // Fixed-priority encoder: lowest index wins
    // -------------------------------------------------------------------------
    always_comb begin
        next_grant_idx   = '0;
        next_grant_found = 1'b0;
        for (int i = NUM_INPUTS-1; i >= 0; i--) begin
            if (s_valid[i]) begin
                next_grant_idx   = $clog2(NUM_INPUTS)'(i);
                next_grant_found = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Grant register – locked for the duration of a frame
    // -------------------------------------------------------------------------
    assign beat_accepted = m_valid & m_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant_idx    <= '0;
            grant_valid  <= 1'b0;
            frame_active <= 1'b0;
        end else begin
            if (frame_active) begin
                // Hold grant until last beat is transferred
                if (beat_accepted && m_last) begin
                    frame_active <= 1'b0;
                    // Immediately re-arbitrate for next frame
                    grant_idx   <= next_grant_idx;
                    grant_valid <= next_grant_found;
                end
            end else begin
                // Idle or just finished: pick highest-priority valid input
                grant_idx   <= next_grant_idx;
                grant_valid <= next_grant_found;
                if (next_grant_found && s_valid[next_grant_idx] && !s_last[next_grant_idx]) begin
                    // New frame is beginning (multi-beat)
                    if (beat_accepted)
                        frame_active <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    always_comb begin
        m_valid = grant_valid & s_valid[grant_idx];
        m_data  = s_data[grant_idx];
        m_keep  = s_keep[grant_idx];
        m_last  = s_last[grant_idx];
        m_user  = s_user[grant_idx];

        // Only assert ready for the currently granted input
        s_ready = '0;
        if (grant_valid)
            s_ready[grant_idx] = m_ready;
    end

    // -------------------------------------------------------------------------
    // One-hot grant output
    // -------------------------------------------------------------------------
    always_comb begin
        grant = '0;
        if (grant_valid)
            grant[grant_idx] = 1'b1;
    end

endmodule

`default_nettype wire
