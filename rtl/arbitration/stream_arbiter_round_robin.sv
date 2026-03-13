// =============================================================================
// Module:       stream_arbiter_round_robin
// Library:      streaming-rtl
// Description:  N-input round-robin AXI-Stream arbiter. The round-robin token
//               advances only after the last beat of a frame is transferred,
//               or when the currently-granted input de-asserts valid while no
//               frame is in progress. This ensures frame atomicity.
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

module stream_arbiter_round_robin #(
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
    logic [$clog2(NUM_INPUTS)-1:0] grant_idx;
    logic                          grant_valid;
    logic                          frame_active;
    logic                          beat_accepted;

    // Round-robin base pointer: search starts *after* last winner
    logic [$clog2(NUM_INPUTS)-1:0] rr_ptr;

    logic [$clog2(NUM_INPUTS)-1:0] next_grant_idx;
    logic                          next_grant_found;

    // -------------------------------------------------------------------------
    // Round-robin priority encoder
    // Searches from rr_ptr+1, wrapping around, for the next valid input.
    // -------------------------------------------------------------------------
    always_comb begin
        next_grant_idx   = '0;
        next_grant_found = 1'b0;
        // Scan from (rr_ptr+1) mod NUM_INPUTS, wrapping around
        for (int i = 0; i < NUM_INPUTS; i++) begin
            if (!next_grant_found &&
                s_valid[(int'(rr_ptr) + 1 + i) % NUM_INPUTS]) begin
                next_grant_idx   = $clog2(NUM_INPUTS)'(
                                       (int'(rr_ptr) + 1 + i) % NUM_INPUTS);
                next_grant_found = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Grant and round-robin pointer registers
    // -------------------------------------------------------------------------
    assign beat_accepted = m_valid & m_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant_idx    <= '0;
            grant_valid  <= 1'b0;
            frame_active <= 1'b0;
            rr_ptr       <= $clog2(NUM_INPUTS)'(NUM_INPUTS - 1);
        end else begin
            if (frame_active) begin
                // Locked to current grant until end-of-frame
                if (beat_accepted && m_last) begin
                    frame_active <= 1'b0;
                    rr_ptr       <= grant_idx;   // advance token past current winner
                    grant_idx    <= next_grant_idx;
                    grant_valid  <= next_grant_found;
                end
            end else begin
                // Idle: track live arbitration result
                if (!grant_valid || !s_valid[grant_idx]) begin
                    // No active grant or current grant lost valid – re-arbitrate
                    grant_idx   <= next_grant_idx;
                    grant_valid <= next_grant_found;
                end
                // Detect start of a multi-beat frame
                if (grant_valid && s_valid[grant_idx] && beat_accepted &&
                    !s_last[grant_idx]) begin
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
