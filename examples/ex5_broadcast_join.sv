// =============================================================================
// Example 5: Broadcast and Join
// =============================================================================
// Description:
//   Demonstrates a fan-out / fan-in topology: one source is broadcast to two
//   independent processing paths, and the processed streams are rejoined into
//   a single output beat whose data contains results from both paths.
//
//   Data flow:
//
//                      ┌─► stream_pipeline_stage (path A) ─┐
//     source ──► stream_broadcast                           ├─► stream_join ──► sink
//                      └─► stream_pipeline_stage (path B) ─┘
//
//   stream_broadcast fans the single input out to both paths simultaneously,
//   using a done-mask to independently track when each output has accepted the
//   current beat.  stream_join waits until both paths present valid data in
//   the same cycle and concatenates their data fields into a single wide beat.
//
//   The output data width is 2*DATA_WIDTH: bits [DATA_WIDTH-1:0] carry path A
//   data and bits [2*DATA_WIDTH-1:DATA_WIDTH] carry path B data.
//
// Parameters:
//   DATA_WIDTH  - Width of each input data bus (default 8)
//
// Interfaces (AXI-Stream ready/valid):
//   source: clk, rst_n, s_valid, s_ready, s_data, s_keep, s_last, s_user
//   sink:   m_valid, m_ready, m_data (2*DATA_WIDTH wide), m_keep, m_last, m_user
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module ex5_broadcast_join #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // Source interface
    input  logic                        s_valid,
    output logic                        s_ready,
    input  logic [DATA_WIDTH-1:0]       s_data,
    input  logic                        s_keep,
    input  logic                        s_last,
    input  logic                        s_user,

    // Sink interface — data is {path_b_data, path_a_data}
    output logic                        m_valid,
    input  logic                        m_ready,
    output logic [2*DATA_WIDTH-1:0]     m_data,
    output logic                        m_keep,
    output logic                        m_last,
    output logic                        m_user
);

    // -------------------------------------------------------------------------
    // Internal wires: broadcast → path A pipeline stage
    // -------------------------------------------------------------------------
    logic                  bcast_a_valid;
    logic                  bcast_a_ready;
    logic [DATA_WIDTH-1:0] bcast_a_data;
    logic                  bcast_a_keep;
    logic                  bcast_a_last;
    logic                  bcast_a_user;

    // -------------------------------------------------------------------------
    // Internal wires: broadcast → path B pipeline stage
    // -------------------------------------------------------------------------
    logic                  bcast_b_valid;
    logic                  bcast_b_ready;
    logic [DATA_WIDTH-1:0] bcast_b_data;
    logic                  bcast_b_keep;
    logic                  bcast_b_last;
    logic                  bcast_b_user;

    // -------------------------------------------------------------------------
    // Internal wires: path A pipeline stage → join
    // -------------------------------------------------------------------------
    logic                  pa_m_valid;
    logic                  pa_m_ready;
    logic [DATA_WIDTH-1:0] pa_m_data;
    logic                  pa_m_keep;
    logic                  pa_m_last;
    logic                  pa_m_user;

    // -------------------------------------------------------------------------
    // Internal wires: path B pipeline stage → join
    // -------------------------------------------------------------------------
    logic                  pb_m_valid;
    logic                  pb_m_ready;
    logic [DATA_WIDTH-1:0] pb_m_data;
    logic                  pb_m_keep;
    logic                  pb_m_last;
    logic                  pb_m_user;

    // -------------------------------------------------------------------------
    // Packed arrays wiring broadcast outputs and join inputs
    // -------------------------------------------------------------------------
    // broadcast m_ ports are packed [NUM_OUTPUTS-1:0]
    logic [1:0]                  bcast_m_valid;
    logic [1:0]                  bcast_m_ready;
    logic [1:0][DATA_WIDTH-1:0]  bcast_m_data;
    logic [1:0]                  bcast_m_keep;
    logic [1:0]                  bcast_m_last;
    logic [1:0]                  bcast_m_user;

    // join s_ ports are packed [NUM_INPUTS-1:0]
    logic [1:0]                  join_s_valid;
    logic [1:0]                  join_s_ready;
    logic [1:0][DATA_WIDTH-1:0]  join_s_data;
    logic [1:0]                  join_s_keep;
    logic [1:0]                  join_s_last;
    logic [1:0]                  join_s_user;

    // Unpack broadcast outputs to named per-path wires
    assign bcast_a_valid = bcast_m_valid[0];
    assign bcast_b_valid = bcast_m_valid[1];
    assign bcast_m_ready[0] = bcast_a_ready;
    assign bcast_m_ready[1] = bcast_b_ready;
    assign bcast_a_data  = bcast_m_data[0];
    assign bcast_b_data  = bcast_m_data[1];
    assign bcast_a_keep  = bcast_m_keep[0];
    assign bcast_b_keep  = bcast_m_keep[1];
    assign bcast_a_last  = bcast_m_last[0];
    assign bcast_b_last  = bcast_m_last[1];
    assign bcast_a_user  = bcast_m_user[0];
    assign bcast_b_user  = bcast_m_user[1];

    // Pack join inputs from named per-path wires
    assign join_s_valid[0] = pa_m_valid;
    assign join_s_valid[1] = pb_m_valid;
    assign pa_m_ready = join_s_ready[0];
    assign pb_m_ready = join_s_ready[1];
    assign join_s_data[0]  = pa_m_data;
    assign join_s_data[1]  = pb_m_data;
    assign join_s_keep[0]  = pa_m_keep;
    assign join_s_keep[1]  = pb_m_keep;
    assign join_s_last[0]  = pa_m_last;
    assign join_s_last[1]  = pb_m_last;
    assign join_s_user[0]  = pa_m_user;
    assign join_s_user[1]  = pb_m_user;

    // -------------------------------------------------------------------------
    // Stage 1: Broadcast — fans source to two output channels
    // -------------------------------------------------------------------------
    stream_broadcast #(
        .NUM_OUTPUTS (2),
        .DATA_WIDTH  (DATA_WIDTH),
        .USER_WIDTH  (1),
        .KEEP_WIDTH  (1)
    ) u_broadcast (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        .m_valid (bcast_m_valid),
        .m_ready (bcast_m_ready),
        .m_data  (bcast_m_data),
        .m_keep  (bcast_m_keep),
        .m_last  (bcast_m_last),
        .m_user  (bcast_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 2a: Path A pipeline stage — registers the data path
    // -------------------------------------------------------------------------
    stream_pipeline_stage #(
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_path_a (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (bcast_a_valid),
        .s_ready (bcast_a_ready),
        .s_data  (bcast_a_data),
        .s_keep  (bcast_a_keep),
        .s_last  (bcast_a_last),
        .s_user  (bcast_a_user),
        .m_valid (pa_m_valid),
        .m_ready (pa_m_ready),
        .m_data  (pa_m_data),
        .m_keep  (pa_m_keep),
        .m_last  (pa_m_last),
        .m_user  (pa_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 2b: Path B pipeline stage — registers the data path
    // -------------------------------------------------------------------------
    stream_pipeline_stage #(
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_path_b (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (bcast_b_valid),
        .s_ready (bcast_b_ready),
        .s_data  (bcast_b_data),
        .s_keep  (bcast_b_keep),
        .s_last  (bcast_b_last),
        .s_user  (bcast_b_user),
        .m_valid (pb_m_valid),
        .m_ready (pb_m_ready),
        .m_data  (pb_m_data),
        .m_keep  (pb_m_keep),
        .m_last  (pb_m_last),
        .m_user  (pb_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Join — combines both paths into one wide output beat
    //
    // m_data = {path_b_data, path_a_data} (2*DATA_WIDTH bits wide)
    // m_last = path_a_last AND path_b_last
    // -------------------------------------------------------------------------
    stream_join #(
        .NUM_INPUTS (2),
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_join (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (join_s_valid),
        .s_ready (join_s_ready),
        .s_data  (join_s_data),
        .s_keep  (join_s_keep),
        .s_last  (join_s_last),
        .s_user  (join_s_user),
        .m_valid (m_valid),
        .m_ready (m_ready),
        .m_data  (m_data),
        .m_keep  (m_keep),
        .m_last  (m_last),
        .m_user  (m_user)
    );

endmodule

`default_nettype wire
