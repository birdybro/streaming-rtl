// =============================================================================
// Module:       stream_broadcast
// Library:      streaming-rtl
// Description:  1:N AXI-Stream broadcaster. Every beat from the single input
//               is forwarded to all N outputs simultaneously. A per-output
//               "done" bitmask tracks which outputs have already accepted the
//               current beat; an output is not offered the beat again once it
//               has acknowledged it. The input beat is accepted (s_ready
//               asserted) only when all outputs have indicated readiness for
//               the current beat.  The done mask is cleared each time a beat
//               is fully dispatched.
//
// Parameters:
//   NUM_OUTPUTS - Number of broadcast outputs (default 4)
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

module stream_broadcast #(
    parameter int unsigned NUM_OUTPUTS = 4,
    parameter int unsigned DATA_WIDTH  = 8,
    parameter int unsigned USER_WIDTH  = 1,
    parameter int unsigned KEEP_WIDTH  = DATA_WIDTH / 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // Slave port (input)
    input  logic                                     s_valid,
    output logic                                     s_ready,
    input  logic [DATA_WIDTH-1:0]                    s_data,
    input  logic [KEEP_WIDTH-1:0]                    s_keep,
    input  logic                                     s_last,
    input  logic [USER_WIDTH-1:0]                    s_user,

    // Master ports (outputs)
    output logic [NUM_OUTPUTS-1:0]                   m_valid,
    input  logic [NUM_OUTPUTS-1:0]                   m_ready,
    output logic [NUM_OUTPUTS-1:0][DATA_WIDTH-1:0]   m_data,
    output logic [NUM_OUTPUTS-1:0][KEEP_WIDTH-1:0]   m_keep,
    output logic [NUM_OUTPUTS-1:0]                   m_last,
    output logic [NUM_OUTPUTS-1:0][USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // "done" bitmask: output i sets its bit when it accepts the current beat.
    // The mask is cleared once ALL outputs have accepted.
    // -------------------------------------------------------------------------
    logic [NUM_OUTPUTS-1:0] done_mask;      // registered: outputs already done
    logic [NUM_OUTPUTS-1:0] done_next;      // combinational next value
    logic                   all_done;       // all outputs accepted this beat

    // -------------------------------------------------------------------------
    // Combinational output valid / ready logic
    // An output receives valid only when the input has valid data AND that
    // output has not yet accepted the current beat.
    // -------------------------------------------------------------------------
    always_comb begin
        // Broadcast data signals to every output unconditionally
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            m_data[i] = s_data;
            m_keep[i] = s_keep;
            m_last[i] = s_last;
            m_user[i] = s_user;
        end

        // Per-output valid: only for outputs that haven't accepted yet
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            m_valid[i] = s_valid & ~done_mask[i];
        end

        // Build next done mask combinationally (current beat)
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            done_next[i] = done_mask[i] | (s_valid & ~done_mask[i] & m_ready[i]);
        end

        all_done = &done_next;

        // Accept input only when all outputs are (or become) done this cycle
        s_ready = s_valid & all_done;
    end

    // -------------------------------------------------------------------------
    // Done mask register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done_mask <= '0;
        end else begin
            if (s_valid) begin
                if (all_done) begin
                    // Beat fully dispatched – clear for next beat
                    done_mask <= '0;
                end else begin
                    // Record newly-acknowledged outputs
                    done_mask <= done_next;
                end
            end
        end
    end

endmodule

`default_nettype wire
