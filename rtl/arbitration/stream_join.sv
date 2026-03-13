// =============================================================================
// Module:       stream_join
// Library:      streaming-rtl
// Description:  N-input AXI-Stream synchronizer (join). Waits until all N
//               input ports present a valid beat simultaneously, then accepts
//               them all in the same clock cycle and presents a single combined
//               output beat whose data payload is the concatenation of all
//               input data fields: {s_data[N-1], ..., s_data[1], s_data[0]}.
//               The m_last output is the logical AND of all s_last inputs,
//               ensuring the output frame ends only when all input frames end
//               simultaneously.  m_keep and m_user are taken from input 0 for
//               simplicity (extend as needed for a specific application).
//
// Parameters:
//   NUM_INPUTS  - Number of stream inputs (default 2)
//   DATA_WIDTH  - Per-input data width in bits (default 8)
//   USER_WIDTH  - User sideband width in bits (default 1)
//   KEEP_WIDTH  - Per-input byte-enable width (default DATA_WIDTH/8)
//
// Output data width: NUM_INPUTS * DATA_WIDTH
//
// Interface:    AXI4-Stream (ready/valid/last/keep/user)
//
// Reset:        Synchronous active-low (rst_n) – purely combinational; rst_n
//               is included for interface consistency.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module stream_join #(
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

    // Master port (output) – data is concatenation of all inputs
    output logic                                     m_valid,
    input  logic                                     m_ready,
    output logic [NUM_INPUTS*DATA_WIDTH-1:0]         m_data,
    output logic [KEEP_WIDTH-1:0]                    m_keep,   // from input 0
    output logic                                     m_last,
    output logic [USER_WIDTH-1:0]                    m_user    // from input 0
);

    // Suppress unused port warnings (no registers needed)
    // synthesis translate_off
    wire _unused = clk & rst_n;
    // synthesis translate_on

    // -------------------------------------------------------------------------
    // All-valid gate: only fire when every input is simultaneously valid
    // -------------------------------------------------------------------------
    logic all_valid;
    assign all_valid = &s_valid;

    assign m_valid = all_valid;
    assign m_keep  = s_keep[0];
    assign m_user  = s_user[0];
    assign m_last  = &s_last;

    // Concatenate input data: m_data[DATA_WIDTH*i +: DATA_WIDTH] = s_data[i]
    genvar gi;
    generate
        for (gi = 0; gi < NUM_INPUTS; gi++) begin : gen_data_concat
            assign m_data[DATA_WIDTH*gi +: DATA_WIDTH] = s_data[gi];
        end
    endgenerate

    // Assert ready to all inputs simultaneously only when downstream is ready
    always_comb begin
        for (int i = 0; i < NUM_INPUTS; i++) begin
            s_ready[i] = all_valid & m_ready;
        end
    end

endmodule

`default_nettype wire
