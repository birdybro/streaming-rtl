// =============================================================================
// Module:       stream_merge
// Library:      streaming-rtl
// Description:  N-input AXI-Stream merge. Frames from the inputs are accepted
//               sequentially in a rotating order: the current input is served
//               until its frame ends (last asserted and beat accepted), then
//               the merge advances to the next input that has valid data.
//               Unlike round-robin arbitration, the merge immediately moves to
//               the next available input after each frame rather than on a
//               cycle-accurate rotation.
//
// Parameters:
//   NUM_INPUTS  - Number of stream inputs (default 2)
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

module stream_merge #(
    parameter int unsigned NUM_INPUTS  = 2,
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
    output logic [USER_WIDTH-1:0]                    m_user
);

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------
    logic [$clog2(NUM_INPUTS)-1:0] cur_idx;      // currently-active input index
    logic                          in_frame;      // a frame is in progress

    logic [$clog2(NUM_INPUTS)-1:0] next_idx;     // combinational: next valid input
    logic                          next_found;

    logic                          beat_accepted;

    // -------------------------------------------------------------------------
    // Priority-encoded next valid input after cur_idx
    // Scans (cur_idx+1) .. (cur_idx+NUM_INPUTS-1) wrapping around.
    // -------------------------------------------------------------------------
    always_comb begin
        next_idx   = '0;
        next_found = 1'b0;
        for (int i = 0; i < NUM_INPUTS; i++) begin
            if (!next_found &&
                s_valid[(int'(cur_idx) + 1 + i) % NUM_INPUTS]) begin
                next_idx   = $clog2(NUM_INPUTS)'(
                                 (int'(cur_idx) + 1 + i) % NUM_INPUTS);
                next_found = 1'b1;
            end
        end
    end

    assign beat_accepted = m_valid & m_ready;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cur_idx  <= '0;
            in_frame <= 1'b0;
        end else begin
            if (in_frame) begin
                // Serve current input until end-of-frame
                if (beat_accepted && s_last[cur_idx]) begin
                    in_frame <= 1'b0;
                    // Immediately switch to next available input
                    if (next_found)
                        cur_idx <= next_idx;
                end
            end else begin
                // Idle: seek next valid input starting after cur_idx
                if (next_found) begin
                    cur_idx <= next_idx;
                    // If it's a multi-beat frame, lock in
                    if (s_valid[next_idx] && beat_accepted && !s_last[next_idx])
                        in_frame <= 1'b1;
                end else if (s_valid[cur_idx]) begin
                    // Current input still has data
                    if (beat_accepted && !s_last[cur_idx])
                        in_frame <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    always_comb begin
        // Determine the effective active index for this cycle
        logic [$clog2(NUM_INPUTS)-1:0] active;
        active = (in_frame || s_valid[cur_idx]) ? cur_idx :
                  (next_found ? next_idx : cur_idx);

        m_valid = s_valid[active];
        m_data  = s_data[active];
        m_keep  = s_keep[active];
        m_last  = s_last[active];
        m_user  = s_user[active];

        s_ready = '0;
        s_ready[active] = m_ready;
    end

endmodule

`default_nettype wire
