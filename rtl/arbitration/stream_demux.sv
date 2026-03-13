// =============================================================================
// Module:       stream_demux
// Library:      streaming-rtl
// Description:  1:N AXI-Stream demultiplexer with external select signal. The
//               input stream is routed to the output port indicated by sel.
//               m_valid is asserted only on the selected output; all others
//               remain deasserted. The input s_ready reflects the m_ready of
//               the currently-selected output port only.
//
// Parameters:
//   NUM_OUTPUTS - Number of stream outputs (default 4)
//   DATA_WIDTH  - Payload data width in bits (default 8)
//   USER_WIDTH  - User sideband width in bits (default 1)
//   KEEP_WIDTH  - Byte-enable width (default DATA_WIDTH/8)
//
// Interface:    AXI4-Stream (ready/valid/last/keep/user)
//
// Reset:        Synchronous active-low (rst_n) – no state is held; rst_n is
//               present for interface consistency and future extension.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module stream_demux #(
    parameter int unsigned NUM_OUTPUTS = 4,
    parameter int unsigned DATA_WIDTH  = 8,
    parameter int unsigned USER_WIDTH  = 1,
    parameter int unsigned KEEP_WIDTH  = DATA_WIDTH / 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // External select (binary-encoded)
    input  logic [$clog2(NUM_OUTPUTS)-1:0]           sel,

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

    // Suppress unused port warnings for consistency
    // synthesis translate_off
    wire _unused = clk & rst_n;
    // synthesis translate_on

    // -------------------------------------------------------------------------
    // Combinational demux – route input to selected output only
    // -------------------------------------------------------------------------
    always_comb begin
        // Default: drive all outputs with input data (but valid only for sel)
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            m_data[i]  = s_data;
            m_keep[i]  = s_keep;
            m_last[i]  = s_last;
            m_user[i]  = s_user;
            m_valid[i] = 1'b0;
        end
        m_valid[sel] = s_valid;

        // Back-pressure from selected output to source
        s_ready = m_ready[sel];
    end

endmodule

`default_nettype wire
