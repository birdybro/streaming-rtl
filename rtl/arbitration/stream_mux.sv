// =============================================================================
// Module:       stream_mux
// Library:      streaming-rtl
// Description:  N:1 AXI-Stream multiplexer with external select signal. The
//               selected input is combinationally passed to the output. The
//               s_ready signal is only asserted for the currently-selected
//               input; all other input ready signals are deasserted. No
//               arbitration logic is included – sel must be driven externally.
//
// Parameters:
//   NUM_INPUTS  - Number of stream inputs (default 4)
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

module stream_mux #(
    parameter int unsigned NUM_INPUTS  = 4,
    parameter int unsigned DATA_WIDTH  = 8,
    parameter int unsigned USER_WIDTH  = 1,
    parameter int unsigned KEEP_WIDTH  = DATA_WIDTH / 8
) (
    input  wire  clk,
    input  wire  rst_n,

    // External select (binary-encoded)
    input  logic [$clog2(NUM_INPUTS)-1:0]            sel,

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

    // Suppress unused port warnings for consistency (no state needed)
    // synthesis translate_off
    wire _unused = clk & rst_n;
    // synthesis translate_on

    // -------------------------------------------------------------------------
    // Combinational select – output driven directly from selected input
    // -------------------------------------------------------------------------
    always_comb begin
        m_valid = s_valid[sel];
        m_data  = s_data[sel];
        m_keep  = s_keep[sel];
        m_last  = s_last[sel];
        m_user  = s_user[sel];

        // Back-pressure only to the selected port
        s_ready = '0;
        s_ready[sel] = m_ready;
    end

endmodule

`default_nettype wire
