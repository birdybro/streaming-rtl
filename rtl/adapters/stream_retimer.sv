// ==============================================================================
// File    : stream_retimer.sv
// Library : streaming-rtl
// Author  : streaming-rtl contributors
// License : MIT
//
// Description:
//   Retimer (single pipeline register stage) for a ready/valid stream.
//   Adds exactly one register stage to help timing closure.  Functionally
//   equivalent to stream_pipeline_stage but explicitly named for use at
//   timing-critical path cuts.
//
//   Handshake: s_ready = m_ready | ~m_valid_r
//
//   When the output register is empty (m_valid_r=0) the stage is always
//   transparent.  When it holds a valid beat (m_valid_r=1) it stalls the
//   upstream unless the downstream is simultaneously consuming (m_ready=1).
//
// Parameters:
//   DATA_WIDTH  – payload width in bits (default 8)
//   USER_WIDTH  – sideband user width in bits (default 1)
//   KEEP_WIDTH  – byte-enable width; should equal DATA_WIDTH/8 (default)
// ==============================================================================

`default_nettype none

module stream_retimer #(
    parameter int DATA_WIDTH = 8,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic clk,
    input  logic rst_n,   // active-low synchronous reset

    // Slave (input) interface
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Master (output) interface
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // Output register
    // -------------------------------------------------------------------------
    logic                   m_valid_r;
    logic [DATA_WIDTH-1:0]  m_data_r;
    logic [KEEP_WIDTH-1:0]  m_keep_r;
    logic                   m_last_r;
    logic [USER_WIDTH-1:0]  m_user_r;

    // We can accept a new beat whenever the output slot is empty or the
    // downstream is simultaneously consuming the current one.
    assign s_ready = m_ready | ~m_valid_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_valid_r <= 1'b0;
            m_data_r  <= '0;
            m_keep_r  <= '0;
            m_last_r  <= 1'b0;
            m_user_r  <= '0;
        end else if (s_ready) begin
            // Latch (or squash) on every cycle the upstream can drive
            m_valid_r <= s_valid;
            m_data_r  <= s_data;
            m_keep_r  <= s_keep;
            m_last_r  <= s_last;
            m_user_r  <= s_user;
        end
    end

    assign m_valid = m_valid_r;
    assign m_data  = m_data_r;
    assign m_keep  = m_keep_r;
    assign m_last  = m_last_r;
    assign m_user  = m_user_r;

endmodule

`default_nettype wire
